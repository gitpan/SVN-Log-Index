# $Id: 02basics.t 61 2004-02-10 00:11:04Z rooneg $

use Test::More tests => 13;
use strict;

use File::Spec::Functions qw(catdir rel2abs);
use File::Temp qw(tempdir);

use SVN::Log::Index;

use Plucene::QueryParser;

my $tmpdir = tempdir (CLEANUP => 1);

my $repospath = rel2abs (catdir ($tmpdir, 'repos'));
my $indexpath = rel2abs (catdir ($tmpdir, 'index'));

{
  system ("svnadmin create $repospath");
  system ("svn mkdir -q file://$repospath/trunk -m 'a log message'");
  system ("svn mkdir -q file://$repospath/branches -m 'another log message'");
}

my $index = SVN::Log::Index->new ($indexpath, create => 1);

isa_ok ($index, 'SVN::Log::Index');

ok ($index->add ("file://$repospath", 1), "added revision via SVN::Ra");

{
  my $hits = $index->search ('log');

  ok (@$hits == 1, "able to retrieve first revision");

  like ($hits->[0]->{message}, qr/message/, 'really matches query');

  my $qp = Plucene::QueryParser->new (
    { analyzer => Plucene::Analysis::SimpleAnalyzer->new (),
      default => 'message' }
  );

  my $query = $qp->parse ('log');

  $hits = $index->search ($query);

  ok (@$hits == 1, 'able to pass a Plucene::Search::Query to search');

  like ($hits->[0]->{message}, qr/log/, 'really matches query');
}

ok ($index->add ($repospath, 2), "added revision with absolute path to repos");

{
  my $hits = $index->search ('another');

  ok (@$hits == 1, "able to retrieve second revision");

  like ($hits->[0]->{message}, qr/another/, 'really matches query');
}

{
  my $hits = $index->search ('log');

  ok (@$hits == 2, "able to retrieve both revisions");

  like ($hits->[0]->{message}, qr/log/, 'really matches query');
  like ($hits->[1]->{message}, qr/log/, 'really matches query');
}

{
  my $indexpath2 = rel2abs (catdir ($tmpdir, 'index2'));

  my $index2 = SVN::Log::Index->new ($indexpath2);

  eval { $index2->add ($repospath, 1); };

  ok (! -e $indexpath2, 'shouldn\'t create a new index if create is false');
}
