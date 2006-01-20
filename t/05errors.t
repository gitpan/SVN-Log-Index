#!/usr/bin/perl

# $Id: 05errors.t 733 2006-01-20 09:38:52Z nik $

use Test::More qw(no_plan);
use strict;
use warnings;

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
  system ("svn mkdir -q file://$repospath/tags -m 'yet another log message'");
}

my $index = SVN::Log::Index->new({ index_path => $indexpath});
isa_ok ($index, 'SVN::Log::Index');

$index->create({ repo_url  => "file://$repospath",
	         overwrite => 1 });
$index->open();

# Start testing that various errors are handled
eval { 
  $index->create();
};
like($@, qr/Can't call create\(\) after open\(\)/,
     'create(),open(),create() fails');

undef $index;
$index = SVN::Log::Index->new({ index_path => $indexpath});
eval {
  $index->create({ repo_url => "file://$repospath",
		   overwrite => 0});
};
like($@, qr/and 'overwrite' is false/,
     'create({overwrite => 0}) works');

eval {
  $index->create({ repo_url => "file://$repospath" });
};
like($@, qr/and 'overwrite' is false/,
     'create() with no explicit overwrite works');

eval {
  $index->create({ overwrite => 1});
};
like($@, qr/called with missing repo_url/,
     'create() with missing repo_url fails');

eval {
  $index->create({ repo_url => undef, overwrite => 1 });
};
like($@, qr/called with undef repo_url/,
     'create() with undef repo_url fails');

eval {
  $index->create({ repo_url => '', overwrite => 1 });
};
like($@, qr/called with empty repo_url/,
     'create() with empty repo_url fails');

$index->create({ repo_url => $repospath, overwrite => 1 });

eval {
  $index->create({ repo_url => $repospath,
		   overwrite => 1, 
		   optimize_every => undef});
};
like($@, qr/undefined optimize_every/,
     'create() with undefined optimize_every fails');

undef $index;
$index = SVN::Log::Index->new({ index_path => '/does/not/exist' });
eval {
  $index->create({ repo_url => $repospath,
		   create => 1 });
};
like($@, qr/Couldn't write into \/does\/not\/exist - it doesn't exist/,
     'Non-existant index_path fails');

# ------------------------------------------------------------------------
#
# Check add()

undef $index;

$index = SVN::Log::Index->new({ index_path => $indexpath});
isa_ok ($index, 'SVN::Log::Index');

$index->create({ repo_url  => "file://$repospath",
	         overwrite => 1 });

eval {
  $index->add();
};
like($@, qr/open\(\) must be called first/,
     'add() before open() fails');

$index->open();

eval {
  $index->add({ end_rev => 'HEAD' });
};
like($@, qr/missing start_rev/,
     'add() missing start_rev fails');

eval {
  $index->add({ start_rev => undef });
};
like($@, qr/start_rev parameter is undef/,
     'add() undef start_rev fails');

eval {
  $index->add({ start_rev => 'foo' });
};
like($@, qr/start_rev value 'foo' is invalid/,
     'add({ start_rev => \'foo\' }) fails');

eval {
  $index->add({ start_rev => -1 });
};
like($@, qr/start_rev value '-1' is invalid/,
     'add({ start_rev => -1 }) fails');
