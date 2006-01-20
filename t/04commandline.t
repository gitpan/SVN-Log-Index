# $Id: 04commandline.t 726 2006-01-11 08:19:33Z nik $

use Test::More tests => 7;
use strict;

use File::Spec::Functions qw(catdir rel2abs);
use File::Temp qw(tempdir);

{
  require SVN::Log;

  $SVN::Log::FORCE_COMMAND_LINE_SVN = 1;
}

use SVN::Log::Index;

my $tmpdir = tempdir (CLEANUP => 1);

my $repospath = rel2abs (catdir ($tmpdir, 'repos'));
my $indexpath = rel2abs (catdir ($tmpdir, 'index'));

eval {
  require SVN::Core;
  require SVN::Ra;
};

SKIP: {
  skip "no reason to force command line tests if we already used it", 6 if $@;

  {
    system ("svnadmin create $repospath");
    system ("svn mkdir -q file://$repospath/trunk -m 'foo'");
    system ("svn mkdir -q file://$repospath/branches -m 'bar'");
  }

  my $index = SVN::Log::Index->new({ index_path => $indexpath });
  $index->create({ repo_url  => $repospath,
		   overwrite => 1 });
  $index->open();

  ok ($index->add({ start_rev => 1 }), "added first revision");

  ok ($index->add({ start_rev => 2 }), "added second revision");

  my $hits = $index->search('foo');

  ok (@$hits == 1, "able to retrieve first revision");

  like ($hits->[0]->{message}, qr/foo/, 'really matches query');

  ok ($hits->[0]->{relevance} > 0.1, 'has a plausible relevance');

  $hits = $index->search ('bar');

  ok (@$hits == 1, "able to retrieve second revision");

  like ($hits->[0]->{message}, qr/bar/, 'really matches query');

  chmod 0600, File::Spec->catfile ($repospath, "format");
};
