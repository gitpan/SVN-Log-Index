# $Id: 03bugs.t 61 2004-02-10 00:11:04Z rooneg $

use Test::More tests => 2;
use strict;

use File::Spec::Functions qw(catdir rel2abs);
use File::Temp qw(tempdir);

use SVN::Log::Index;

my $tmpdir = tempdir (CLEANUP => 1);

my $repospath = rel2abs (catdir ($tmpdir, 'repos'));
my $indexpath = rel2abs (catdir ($tmpdir, 'index'));

{
  system ("svnadmin create $repospath");
  system ("svn mkdir -q file://$repospath/trunk -m ''");
  system ("svn mkdir -q file://$repospath/branches -m ' \t \n'");
}

my $index = SVN::Log::Index->new ($indexpath, create => 1);

ok ($index->add ("file://$repospath", 1), "added revision with empty log");

ok ($index->add ("file://$repospath", 2), "added revision with whitespace log");
