# $Id: 04commandline.t 159 2004-06-11 23:58:12Z rooneg $

use Test::More tests => 6;
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

  my $index = SVN::Log::Index->new ($indexpath, create => 1);

  ok ($index->add ("file://$repospath", 1), "added first revision");

  ok ($index->add ("file://$repospath", 2), "added second revision");

  my $hits = $index->search ('foo');

  ok (@$hits == 1, "able to retrieve first revision");

  like ($hits->[0]->{message}, qr/foo/, 'really matches query');

  $hits = $index->search ('bar');

  ok (@$hits == 1, "able to retrieve second revision");

  like ($hits->[0]->{message}, qr/bar/, 'really matches query');

  chmod 0600, File::Spec->catfile ($repospath, "format");
};
