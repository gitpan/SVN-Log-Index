package SVN::Log::Index;

# $Id: Index.pm 127 2004-05-28 00:38:48Z rooneg $

use strict;

use Plucene::Document;
use Plucene::Document::Field;
use Plucene::Index::Writer;
use Plucene::Analysis::SimpleAnalyzer;
use Plucene::Search::IndexSearcher;
use Plucene::QueryParser;

our $VERSION = '0.21';

=head1 NAME

SVN::Log::Index - Index and search over Subversion commit logs.

=head1 SYNOPSIS

  my $index = SVN::Log::Index->new ('/path/to/index');

  $index->add ('svn://host/repos', 1);

  my $results = $index->search ('query');

=head1 DESCRIPTION

SVN::Log::Index builds a Plucene index of commit logs from any number of 
Subversion repositories and allows you to do arbitrary full text searches 
over them.

=head1 METHODS

=head2 new

  my $index = SVN::Log::Index->new ('/path/to/index', create => $create);

Create a new index or an object to manage an existing index.

The first argument is the path to the index on disk, and all remaining 
arguments are used to create an args hash.

If the args hash's 'create' entry is true a new index will be created, 
otherwise an existing index will be opened.

=cut

sub new {
  my ($class, $path, %args) = @_;

  $args{index_path}     = $path;
  $args{optimize_count} = 100; # this is a stupid name
  $args{index_count}    = 0; # so is this

  bless \%args, $class;
}

sub _open_writer {
  my $self = shift;

  $self->{writer}
    = Plucene::Index::Writer->new ($self->{index_path},
                                   Plucene::Analysis::SimpleAnalyzer->new (),
                                   $self->{create})
    or die "error opening index: $!";
}

sub _handle_log {
  my ($self, $paths, $rev, $author, $date, $msg, $pool) = @_;

  my $doc = Plucene::Document->new ();

  $doc->add (Plucene::Document::Field->Keyword ("revision", $rev));

  # it's certainly possible to get a undefined author, you just need either 
  # mod_dav_svn with no auth, or svnserve with anonymous write access turned 
  # on.
  $doc->add (Plucene::Document::Field->Text ("author", $author))
    if defined $author;

  # XXX might want to convert the date to something more easily searchable, 
  # but for now let's settle for just not tokenizing it.
  $doc->add (Plucene::Document::Field->Keyword ("date", $date));

  $doc->add (Plucene::Document::Field->Text ("paths", join '\n',
                                             keys %$paths))
    if defined $paths; # i'm still not entirely clear how this can happen...

  $doc->add (Plucene::Document::Field->Text ("message", $msg))
    unless $msg =~ m/^\s*$/;

  $doc->add (Plucene::Document::Field->Keyword ("url", $self->{url}));

  $self->{writer}->add_document ($doc);

  if ($self->{index_count}++ == $self->{optimize_count}) {
    $self->{writer}->optimize ();

    $self->_open_writer ();
  }
}

=head2 add

  $index->add ('svn://host/path/to/repos', $start_rev, $end_rev);

Add one or more log messages to the index.  If a second revision is not 
specified, the revision passed will be added to the index, otherwise the 
range of revisions from $start_rev to $end_rev will be added.

=cut

sub add {
  # we only pull this in here so that the search portions of this module 
  # can be used in environments where the svn libs can't be linked against.
  #
  # this can happen, for example, when apache and mod_perl2 are linked 
  # against different versions of the APR libraries than subversion is.
  #
  # not that i happen to have a system like that or anything...
  eval {
    require SVN::Core;
    require SVN::Ra;
  };

  if ($@) {
    # oops, we don't have the SVN perl libs installed, so instead we need
    # to fall back to using the command line client the old fashioned way
    *_do_log = *_do_log_commandline;
  } else {
    *_do_log = *_do_log_bindings;
  }

  # alias add to _add, so we only do the require the first time through.
  *add = *_add;

  # let's try this again...
  add (@_);
}

sub _do_log_bindings {
  my ($self, $repos, $start_rev, $end_rev) = @_;

  my $r = SVN::Ra->new (url => $repos) or die "error opening RA layer: $!";

  $r->get_log ([''], $start_rev, $end_rev, 1, 0,
               sub { $self->_handle_log (@_); });
}

sub _do_log_commandline {
  my ($self, $repos, $start_rev, $end_rev) = @_;

  open my $log, "svn log -v -r $start_rev:$end_rev $repos|"
    or die "couldn't open pipe to svn process: $!";

  my ($paths, $rev, $author, $date, $msg);

  my $state = 'start';

  my $seprule  = qr/^-{72}$/;
  my $headrule = qr/r(\d+) \| (\w+) \| (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/;

  # XXX i'm sure this can be made much much cleaner...
  while (<$log>) {
    if ($state eq 'start' or $state eq 'message' and m/$seprule/) {
      if ($state eq 'start') {
        $state = 'head';
      } elsif ($state eq 'message') {
        $state = 'start';
        $self->_handle_log($paths, $rev, $author, $date, $msg);
      }
    } elsif ($state eq 'head' and m/$headrule/) {
      $rev = $1;
      $author = $2;
      $date = $3;
      $paths = {};
      $msg = "";

      $state = 'paths';
    } elsif ($state eq 'paths') {
      unless (m/^Changed paths:$/) {
        if (m/^$/) {
          $state = 'message';
        } else {
          if (m/^\s+\w+ (.+)$/) {
            $paths->{$1} = 1; # we only care about the filename anyway...
          }
        }
      }
    } elsif ($state eq 'message') {
      $msg .= $_;
    }
  }
}

sub _add {
  my ($self, $repos, $start_rev, $end_rev) = @_;

  $end_rev = $start_rev unless defined $end_rev;

  $self->_open_writer ();

  delete $self->{create} if $self->{create};

  $self->{url} = $repos;

  unless ($repos =~ m/^(http|https|svn|file|svn\+ssh):\/\//) {
    $repos = "file://$repos";
  }

  $self->_do_log ($repos, $start_rev, $end_rev);

  undef $self->{writer};
  undef $self->{url};

  1;
}

=head2 search

  my $hits = $index->search ($query);

Search for $query (which is parsed into a Plucene::Search::Query object by 
the Plucene::QueryParser module) in $index and return a reference to an array 
of hash references.  Each hash reference points to a hash where the key is 
the field name and the value is the field value for all the fields associated 
with the hit.

=cut

sub search {
  my ($self, $query, %args) = @_;

  my $plucene_query;

  if (ref $query and $query->isa ('Plucene::Search::Query')) {
    $plucene_query = $query;
  } else {
    my $a = Plucene::Analysis::SimpleAnalyzer->new ();

    my $qp = Plucene::QueryParser->new ({ analyzer => $a,
                                          default => 'message' });

    $plucene_query = $qp->parse ($query);
  }

  my $searcher = Plucene::Search::IndexSearcher->new ($self->{index_path});

  my @results;

  my $reader = $searcher->reader;

  my $hc = Plucene::Search::HitCollector->new (collect =>
    sub {
      my ($self, $docid, $score) = @_;

      my $doc = $reader->document ($docid);

      my %result;

      for my $key qw(revision message author paths date url) {
        my $field = $doc->get ($key);

        $result{$key} = $field->string if defined $field;
      }

      push @results, \%result;
    }
  );

  $searcher->search_hc ($plucene_query, $hc);

  return \@results;
}

=head1 AUTHOR

Garrett Rooney, <rooneg@electricjellyfish.net> 

=head1 LICENSE

This software is licensed under the same terms as Perl itself.

=cut

1;
