#!/usr/bin/perl -w

# $Id: Build.PL 98 2004-03-01 00:33:24Z rooneg $

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

eval {
  require SVN::Core;
  require SVN::Ra;
};

if ($@) {
  unless (have_exe ('svn')) {
    print <<EOM;
SVN::Log::Index requires either the SVN perl bindings or the 'svn' executable 
to function.

You can obtain both at http://subversion.tigris.org/.
EOM
    exit 1;
  }
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
  },

  recommends => {
    'SVN::Core' => 0,
  },
)->create_build_script;
