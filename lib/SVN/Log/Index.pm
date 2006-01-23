package SVN::Log::Index;

use strict;
use warnings;

use Plucene::Document;
use Plucene::Document::Field;
use Plucene::Index::Writer;
use Plucene::Analysis::SimpleAnalyzer;
use Plucene::Search::IndexSearcher;
use Plucene::QueryParser;

use SVN::Log;
use Carp;
use YAML ();

our $VERSION = '0.41';

=head1 NAME

SVN::Log::Index - Index and search over Subversion commit logs.

=head1 SYNOPSIS

  my $index = SVN::Log::Index->new({ index_path => '/path/to/index' });

  if($creating) {    # Create from scratch if necessary
    $index->create({ repo_url => 'url://for/repo' });
  }

  $index->open();    # And then open it

  # Now add revisions from the repo to the index
  $index->add({ start_rev => $start_rev,
                end_rev   => $end_rev);

  # And query the index
  my $results = $index->search('query');

=head1 DESCRIPTION

SVN::Log::Index builds a Plucene index of commit logs from a
Subversion repository and allows you to do arbitrary full text searches
over it.

=head1 METHODS

=head2 new

  # Creating a new index object
  my $index = SVN::Log::Index->new({index_path => '/path/to/index'});

Create a new index object.

The single argument is a hash ref.  Currently only one key is valid.

=over 4

=item index_path

The path that contains (or will contain) the index files.

=back

This method prepares the object for use, but does not make any changes
on disk.

=cut

sub new {
  my $proto = shift;
  my $args  = shift;

  my $class = ref($proto) || $proto;
  my $self  = {};

  $self->{index_path} = $args->{index_path};

  bless $self, $class;
}

=head2 create

  $index->create({ repo_url       => 'url://for/repo',
                   analyzer_class => 'Plucene::Analysis::Analyzer::Sub',
                   optimize_every => $num,
                   overwrite      => 1, # or 0
               });

This method creates a new index, in the C<index_path> given when the
object was created.

The single argument is a hash ref, with the following possible keys.

=over 4

=item repo_url

The URL for the Subversion repository that is going to be indexed.

=item analyzer_class

A string giving the name of the class that will analyse log message
text and tokenise it.  This should derive from the
L<Plucene::Analysis::Analyzer> class.  SVN::Log::Index will call this
class' C<new()> method.

Once an analyzer class has been chosen for an index it can not be
changed without deleting the index and creating it afresh.

The default value is C<Plucene::Analysis::SimpleAnalyzer>.

=item optimize_every

Per the documentation for L<Plucene::Index::Writer>, the index should
be optimized to improve search performance.

This is normally done after an application has finished adding documents
to the index.  However, if your application will be using the index while
it's being updated you may wish the optimisation to be carried out
periodically while the repository is still being indexed.

If defined, the index will be optimized after every C<optimize_every>
revisions have been added to the index.  The index is also optimized
after the final revision has been added.

So if C<optimize_every> is given as C<100>, and you have requested
that revisions 134 through 568 be indexed then the index will be
optimized after adding revision 200, 300, 400, 500, and 568.

The default value is 0, indicating that optimization should only be
carried out after the final revision has been added.

=item overwrite

A boolean indicating whether or not a pre-existing index_path should
be overwritten.

Given this sequence;

  my $index = SVN::Log::Index->new({index_path => '/path'});
  $index->create({repo_url => 'url://for/repo'});

The call to C<create()> will fail if C</path> already exists.

If C<overwrite> is set to a true value then C</path> will be cleared.

=back

After creation the index directory will exist on disk, and a
configuration file containing the create()-time parameters will be
created in the index directory.

Newly created indexes must still be opened.

=cut

my %default_opts = (analyzer_class => 'Plucene::Analysis::SimpleAnalyzer',
		    optimize_every => 0,
		    overwrite => 0,
		    );

sub create {
  my $self = shift;
  my $args = shift;

 croak "Can't call create() after open()" if exists $self->{config};

  my %opts = (%default_opts, %$args);

  if(-d $self->{index_path} and ! $opts{overwrite}) {
    croak "create() $self->{index_path} exists and 'overwrite' is false";
  }

  croak "create() called with missing repo_url" if ! exists $opts{repo_url};
  croak "create() called with undef repo_url" if ! defined $opts{repo_url};
  croak "create() called with empty repo_url" if $opts{repo_url} =~ /^\s*$/;
  croak "create() called with undefined optimize_every" if ! defined $opts{optimize_every};

  if($opts{repo_url} !~ m/^(http|https|svn|file|svn\+ssh):\/\//) {
    $opts{repo_url} = 'file://' . $opts{repo_url};
  }

  $self->{config} = \%opts;
  $self->{config}{last_indexed_rev} = 0;

  $self->_create_analyzer();
  $self->_create_writer($opts{overwrite});

  $self->_save_config();

  delete $self->{config};	# Gets reloaded in open()
}

sub _save_config {
  my $self = shift;

  YAML::DumpFile($self->{index_path} . '/config.yaml', $self->{config})
      or croak "Saving config failed: $!";
}

sub _load_config {
  my $self = shift;

  $self->{config} = YAML::LoadFile($self->{index_path} . '/config.yaml')
    or croak "Could not load state from $self->{index_path}/config.yaml: $!";
}

sub _create_writer {
  my $self = shift;
  my $create = shift;

  return if exists $self->{writer} and defined $self->{analyzer};

  croak "_create_analyzer() must be called first" if ! exists $self->{analyzer};
  croak "analyzer is empty" if ! defined $self->{analyzer};

  $self->{writer} = Plucene::Index::Writer->new($self->{index_path},
						$self->{analyzer},
						$create)
    or croak "error creating ::Writer object: $!";
}

sub _create_analyzer {
  my $self = shift;

  return if exists $self->{analyzer} and defined $self->{analyzer};

  $self->{analyzer} = $self->{config}{analyzer_class}->new()
    or croak "error creating $self->{config}{analyzer_class} object: $!";
}

=head2 open

  $index->open();

Opens the index, in preparation for adding or removing entries.

=cut

sub open {
  my $self = shift;
  my $args = shift;

  croak "$self->{index_path} does not exist" if ! -d $self->{index_path};
  croak "$self->{index_path}/config.yaml does not exist" if ! -f "$self->{index_path}/config.yaml";

  $self->_load_config();
  $self->_create_analyzer();
}

=head2 add

  $index->add ({ start_rev      => $start_rev,  # number, or 'HEAD'
                 end_rev        => $end_rev,    # number, or 'HEAD'
                 optimize_every => $num });

Add one or more log messages to the index.

The single argument is a hash ref, with the following possible keys.

=over

=item start_rev

The first revision to add to the index.  May be given as C<HEAD> to mean
the repository's most recent (youngest) revision.

This key is mandatory.

=item end_rev

The last revision to add to the index.  May be given as C<HEAD> to mean
the repository's most recent (youngest) revision.

This key is optional.  If not included then only the revision specified
by C<start_rev> will be indexed.

=item optimize_every

Overrides the C<optimize_every> value that was given in the C<create()>
call that created this index.

This key is optional.  If it is not included then the value used in the
C<create()> call is used.  If it is included, and the value is C<undef>
then optimization will be disabled while these revisions are included.

The index will still be optimized after the revisions have been added.

=back

Revisions from C<start_rev> to C<end_rev> are added inclusive.
C<start_rev> and C<end_rev> may be given in ascending or descending order.
Either:

  $index->add({ start_rev => 1, end_rev => 10 });

or

  $index->add({ start_rev => 10, end_rev => 1 });

In both cases, revisons are indexed in ascending order, so revision 1,
followed by revision 2, and so on, up to revision 10.

=cut

sub add {
  my $self = shift;
  my $args = shift;

  croak "open() must be called first" unless exists $self->{config};
  croak "add() missing start_rev parameter" unless exists $args->{start_rev};
  croak "add() start_rev parameter is undef" unless defined $args->{start_rev};

  $args->{end_rev} = $args->{start_rev} unless defined $args->{end_rev};

  foreach (qw(start_rev end_rev)) {
    croak "$_ value '$args->{$_}' is invalid"
      if $args->{$_} !~ /^(?:\d+|HEAD)$/;
  }

  # Get start_rev and end_rev in to ascending order.
  if($args->{start_rev} ne $args->{end_rev} and $args->{end_rev} ne 'HEAD') {
    if(($args->{start_rev} eq 'HEAD') or ($args->{start_rev} > $args->{end_rev})) {
      ($args->{start_rev}, $args->{end_rev}) =
	($args->{end_rev}, $args->{start_rev});
    }
  }

  $self->_create_writer(0);

  my $optimize = $self->{config}{optimize_every};
  $optimize = $args->{optimize_every}
    if exists $args->{optimize_every} and defined $args->{optimize_every};

  SVN::Log::retrieve ({ repository => $self->{config}{repo_url},
                        start      => $args->{start_rev},
                        end        => $args->{end_rev},
                        callback   => sub { $self->_handle_log({ rev => \@_,
								 optimize_every => $optimize }); } });

  $self->{writer}->optimize();

  delete $self->{writer};
}

sub _handle_log {
  my ($self, $args) = @_;

  my ($paths, $rev, $author, $date, $msg) = @{$args->{rev}};

  my $doc = Plucene::Document->new ();

  $doc->add (Plucene::Document::Field->Keyword ("revision", "$rev"));

  # it's certainly possible to get a undefined author, you just need either
  # mod_dav_svn with no auth, or svnserve with anonymous write access turned
  # on.
  $doc->add (Plucene::Document::Field->Text ("author", $author))
    if defined $author;

  # XXX might want to convert the date to something more easily searchable,
  # but for now let's settle for just not tokenizing it.
  $doc->add (Plucene::Document::Field->Keyword("date", $date));

  $doc->add (Plucene::Document::Field->Text("paths", join '\n',
					    keys %$paths))
    if defined $paths; # i'm still not entirely clear how this can happen...

  $doc->add (Plucene::Document::Field->Text("message", $msg))
    unless $msg =~ m/^\s*$/;

  $self->{writer}->add_document($doc);

  $self->{config}{last_indexed_rev} = $rev;

  $self->_save_config();

  if($args->{optimize_every}){
    if($self->{config}{last_indexed_rev} % $args->{optimize_every} == 0) {
      $self->{writer}->optimize();
      delete $self->{writer};
      $self->_create_writer(0);
    }
  }
}

=head2 get_last_indexed_rev

  my $rev = $index->get_last_indexed_rev();

Returns the revision number that was most recently added to the index.

Most useful in repeated calls to C<add()>.

  # Loop forever.  Every five minutes wake up, and add all newly
  # committed revisions to the index.
  while(1) {
    sleep 300;
    $index->add({ start_rev => $index->get_last_indexed_rev() + 1,
                  end_rev   => 'HEAD' });
  }

The last indexed revision number is saved as a property of the index.

=cut

sub get_last_indexed_rev {
  my $self = shift;

  croak "Can't call get_last_indexed_rev() before open()"
    unless exists $self->{config};
  croak "Empty configuration" unless defined $self->{config};

  return $self->{config}{last_indexed_rev};
}

=head2 search

  my $hits = $index->search ($query);

Search for $query (which is parsed into a Plucene::Search::Query object by
the Plucene::QueryParser module) in $index and return a reference to an array
of hash references.  Each hash reference points to a hash where the key is
the field name and the value is the field value for this hit.

The keys are:

=over

=item relevance

How relevant Plucene thought this result was, as a floating point number.

=item url

The URL of the repository that the index is for.

=item revision, message, author, paths, date

The revision number, log message, commit author, paths changed in the commit,
and date of the commit, respectively.

=back

=cut

sub search {
  my ($self, $query, %args) = @_;

  croak "open() must be called first" unless exists $self->{config};

  my $plucene_query;

  if (ref $query and $query->isa ('Plucene::Search::Query')) {
    $plucene_query = $query;
  } else {
    my $qp = Plucene::QueryParser->new ({ analyzer => $self->{analyzer},
                                          default => 'message' });

    $plucene_query = $qp->parse ($query);
  }

  my $searcher = Plucene::Search::IndexSearcher->new ($self->{index_path});

  my @results;

  my $reader = $searcher->reader;

  # $self isn't usable in the HitCollector collect sub, so the repo url
  # isn't available.  Copy it in to a separate variable so that it's in
  # scope for the HitCollector sub.

  my $repo_url = $self->{config}{repo_url};

  my $hc = Plucene::Search::HitCollector->new (collect =>
    sub {
      my ($self, $docid, $score) = @_;

      my $doc = $reader->document ($docid);

      my %result = (relevance => $score,
                    url       => $repo_url);

      for my $key qw(revision message author paths date) {
        my $field = $doc->get ($key);

        $result{$key} = $field->string if defined $field;
      }

      push @results, \%result;
    }
  );

  $searcher->search_hc ($plucene_query, $hc);

  return \@results;
}

=head1 QUERY SYNTAX

This module supports the Lucene query syntax, described in detail at
L<http://lucene.apache.org/java/docs/queryparsersyntax.html>.  A brief
overview follows.

=over

=item *

A query consists of one or more terms, joined with boolean operators.

=item *

A term is either a single word, or two or more words, enclosed in double
quotes.  So

  foo bar baz

is a different query from

  "foo bar" baz

The first searches for any of C<foo>, C<bar>, or C<baz>, the second
searches for any of C<foo bar>, or C<baz>.

=item *

By default, multiple terms in a query are OR'd together.  You may also
use C<AND>, or C<NOT> between terms.

  foo AND bar
  foo NOT bar

Use C<+> before a term to indicate that it must appear, and C<->
before a term to indicate that it must not appear.

  foo +bar
  -foo bar

=item *

Use parantheses to control the ordering.

  (foo OR bar) AND baz

=item *

Searches are conducted in I<fields>.  The default field to search is
the log message.  Other fields are indicated by placing the field name
before the term, separating them both with a C<:>.

Available fields are:

=over

=item revision

=item author

=item date

=item paths

=back

For example, to find all commit messages where C<nik> was the committer,
that contained the string "foo bar":

  author:nik AND "foo bar"

=back

=head1 SEE ALSO

L<SVN::Log>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-svn-log-index@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SVN-Log-Index>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 AUTHOR

The current maintainer is Nik Clayton, <nikc@cpan.org>.

The original author was Garrett Rooney, <rooneg@electricjellyfish.net>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 Nik Clayton.  All Rights Reserved.

Copyright 2004 Garrett Rooney.  All Rights Reserved.

This software is licensed under the same terms as Perl itself.

=cut

1;
