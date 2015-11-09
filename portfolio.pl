#!/usr/bin/perl -w
#
## Debugging
##
## database input and output is paired into the two arrays noted
##
my $debug=0; # default - will be overriden by a form parameter or cookie
my @sqlinput=();
my @sqloutput=();
#
##
## The combination of -w and use strict enforces various 
## rules that make the script more resilient and easier to run
## as a CGI script.
##
use strict;
use warnings;


# The CGI web generation stuff
# # This helps make it easy to generate active HTML content
# # from Perl
# #
# # We'll use the "standard" procedural interface to CGI
# # instead of the OO default interface
use CGI qw(:standard);

# The interface to the database.  The interface is essentially
# # the same no matter what the backend database is.  
# #
# # DBI is the standard database interface for Perl. Other
# # examples of such programatic interfaces are ODBC (C/C++) and JDBC (Java).
# #
# #
# # This will also load DBD::Oracle which is the driver for
# # Oracle.
use DBI;


#
##
## A module that makes it easy to parse relatively freeform
## date strings into the unix epoch time (seconds since 1970)
##
use Time::ParseDate;
#
#
#
##
## You need to override these for access to your database
##
my $dbuser="jrp338";
my $dbpasswd="zp97npGDx";


#
## The session cookie will contain the user's name and password so that 
## he doesn't have to type it again and again. 
##
## "RWBSession"=>"user/password"
##
## BOTH ARE UNENCRYPTED AND THE SCRIPT IS ALLOWED TO BE RUN OVER HTTP
## THIS IS FOR ILLUSTRATION PURPOSES.  IN REALITY YOU WOULD ENCRYPT THE COOKIE
## AND CONSIDER SUPPORTING ONLY HTTPS
##
my $cookiename="PortfolioSession";
##
## And another cookie to preserve the debug state
##
my $debugcookiename="PortfolioDebug";
#
##
## Get the session input and debug cookies, if any
##
my $inputcookiecontent = cookie($cookiename);
my $inputdebugcookiecontent = cookie($debugcookiename);
#
##
## Will be filled in as we process the cookies and paramters
##
my $outputcookiecontent = undef;
my $outputdebugcookiecontent = undef;
my $deletecookie=0;
my $user = undef;
my $password = undef;
my $logincomplain=0;

#
## Get the user action and whether he just wants the form or wants us to
## run the form
##
my $action;
my $run;


if (defined(param("act"))) {
  $action=param("act");
  if (defined(param("run"))) {
    $run = param("run") == 1;
  } else {
    $run = 0;
  }
} else {
  $action="base";
  $run = 1;
}

my $dstr;

if (defined(param("debug"))) {
  if (param("debug") == 0) {
    $debug = 0;
  } else {
    $debug = 1;
  }
} else {
  if (defined($inputdebugcookiecontent)) {
    $debug = $inputdebugcookiecontent;
  } else {
  }
}

$outputdebugcookiecontent=$debug;


if (defined($inputcookiecontent)) { 
  ($user,$password) = split(/\//,$inputcookiecontent);
  $outputcookiecontent = $inputcookiecontent;
} else {
  ($user,$password) = ("anon","anonanon");
}   
