#!/usr/bin/perl -w

# $Id: Build.PL 153 2004-06-11 20:11:20Z rooneg $

use strict;
use warnings;

use Module::Build;

use Config;
use File::Spec;

sub have_exe {
  my $name = shift;

  my @dirs = split ':', $ENV{PATH};

  my $found_exe = 0;

  for (@dirs) {
    $found_exe = 1 if (-x File::Spec->catdir ($_, "$name$Config{_exe}"));
  }

  return $found_exe;
}

unless (have_exe ('svnadmin')) {
  print <<EOM;
SVN::Log::Index requires the 'svnadmin' executable to run it's tests.

You don't seem to have it, so don't be too surprised when they fail.
EOM
}

Module::Build->new (
  dist_name => 'SVN-Log-Index',

  license => 'perl',

  module_name => 'SVN::Log::Index',

  create_makefile_pl => 'passthrough',

  create_readme => 1,

  script_files => [
    'bin/sli',
  ],

  requires => {
    'Plucene' => 1.0,
    'SVN::Log' => 0,
  },

  recommends => {
    'SVN::Core' => 0,
  },
)->create_build_script;
