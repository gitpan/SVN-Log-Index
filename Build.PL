#!/usr/bin/perl -w

# $Id: Build.PL 53 2004-02-04 00:31:14Z rooneg $

use strict;
use warnings;

use Module::Build;

Module::Build->new(
  dist_name => 'SVN-Log-Index',

  license => 'perl',

  module_name => 'SVN::Log::Index',

  create_makefile_pl => 'passthrough',

  create_readme => 1,

  script_files => [
    'bin/sli',
  ],

  requires     => {
    'SVN::Core'           => 0,
    'PLucene'             => 1.0,
  },
)->create_build_script;
