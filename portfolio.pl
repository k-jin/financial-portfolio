#!/usr/bin/perl -w

#
#
# rwb.pl (Red, White, and Blue)
#
#
# Example code for EECS 339, Northwestern University
# 
# Peter Dinda
#

# The overall theory of operation of this script is as follows
#
# 1. The inputs are form parameters, if any, and a session cookie, if any. 
# 2. The session cookie contains the login credentials (User/Password).
# 3. The parameters depend on the form, but all forms have the following three
#    special parameters:
#
#         act      =  form  <the form in question> (form=base if it doesn't exist)
#         run      =  0 Or 1 <whether to run the form or not> (=0 if it doesn't exist)
#         debug    =  0 Or 1 <whether to provide debugging output or not> 
#
# 4. The script then generates relevant html based on act, run, and other 
#    parameters that are form-dependent
# 5. The script also sends back a new session cookie (allowing for logout functionality)
# 6. The script also sends back a debug cookie (allowing debug behavior to propagate
#    to child fetches)
#


#
# Debugging
#
# database input and output is paired into the two arrays noted
#
my $debug=0; # default - will be overriden by a form parameter or cookie
my @sqlinput=();
my @sqloutput=();

#
# The combination of -w and use strict enforces various 
# rules that make the script more resilient and easier to run
# as a CGI script.
#
use strict;
use warnings;
#use MIME::LITE::TT:HTML;
#use Email::MIME;

# The CGI web generation stuff
# This helps make it easy to generate active HTML content
# from Perl
#
# We'll use the "standard" procedural interface to CGI
# instead of the OO default interface
use CGI qw(:standard);


# The interface to the database.  The interface is essentially
# the same no matter what the backend database is.  
#
# DBI is the standard database interface for Perl. Other
# examples of such programatic interfaces are ODBC (C/C++) and JDBC (Java).
#
#
# This will also load DBD::Oracle which is the driver for
# Oracle.
use DBI;

#
#
# A module that makes it easy to parse relatively freeform
# date strings into the unix epoch time (seconds since 1970)
#
use Time::ParseDate;



#
# You need to override these for access to your database
#
my $dbuser="jrp338";
my $dbpasswd="zp97npGDx";


#
# The session cookie will contain the user's name and password so that 
# he doesn't have to type it again and again. 
#
# "RWBSession"=>"user/password"
#
# BOTH ARE UNENCRYPTED AND THE SCRIPT IS ALLOWED TO BE RUN OVER HTTP
# THIS IS FOR ILLUSTRATION PURPOSES.  IN REALITY YOU WOULD ENCRYPT THE COOKIE
# AND CONSIDER SUPPORTING ONLY HTTPS
#
my $cookiename="RWBSession";
#
# And another cookie to preserve the debug state
#
my $debugcookiename="RWBDebug";

#
# Get the session input and debug cookies, if any
#
my $inputcookiecontent = cookie($cookiename);
my $inputdebugcookiecontent = cookie($debugcookiename);

#
# Will be filled in as we process the cookies and paramters
#
my $outputcookiecontent = undef;
my $outputdebugcookiecontent = undef;
my $deletecookie=0;
my $user = undef;
my $password = undef;
my $logincomplain=0;

#
# Get the user action and whether he just wants the form or wants us to
# run the form
#
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
  $action="login";
  $run = 1;
}

my $dstr;

if (defined(param("debug"))) { 
  # parameter has priority over cookie
  if (param("debug") == 0) { 
    $debug = 0;
  } else {
    $debug = 1;
  }
} else {
  if (defined($inputdebugcookiecontent)) { 
    $debug = $inputdebugcookiecontent;
  } else {
    # debug default from script
  }
}

$outputdebugcookiecontent=$debug;

#
#
# Who is this?  Use the cookie or anonymous credentials
#
#
if (defined($inputcookiecontent)) { 
  # Has cookie, let's decode it
  ($user,$password) = split(/\//,$inputcookiecontent);
  $outputcookiecontent = $inputcookiecontent;
} else {
  # No cookie, treat as anonymous user
  ($user,$password) = ("anon","anonanon");
}

#
# Is this a login request or attempt?
# Ignore cookies in this case.
#
if ($action eq "login") { 
  if ($run) { 
    #
    # Login attempt
    #
    # Ignore any input cookie.  Just validate user and
    # generate the right output cookie, if any.
    #
    my $email = param('email');
    ($user,$password) = (param('user'),param('password'));
    if (ValidUser($user,$email,$password)) { 
      # if the user's info is OK, then give him a cookie
      # that contains his username and password 
      # the cookie will expire in one hour, forcing him to log in again
      # after one hour of inactivity.
      # Also, land him in the base query screen
      $outputcookiecontent=join("/",$user,$password);
      $action = "base";
      $run = 1;
    } else {
      # uh oh.  Bogus login attempt.  Make him try again.
      # don't give him a cookie
      $logincomplain=1;
      $action="login";
      $run = 0;
    }
  } else {
    #
    # Just a login screen request, but we should toss out any cookie
    # we were given
    #
    undef $inputcookiecontent;
    ($user,$password)=("anon","anonanon");
  }
} 


#
# If we are being asked to log out, then if 
# we have a cookie, we should delete it.
#
if ($action eq "logout") {
  $deletecookie=1;
  $action = "base";
  $user = "anon";
  $password = "anonanon";
  $run = 1;
}


my @outputcookies;

#
# OK, so now we have user/password
# and we *may* have an output cookie.   If we have a cookie, we'll send it right 
# back to the user.
#
# We force the expiration date on the generated page to be immediate so
# that the browsers won't cache it.
#
if (defined($outputcookiecontent)) { 
  my $cookie=cookie(-name=>$cookiename,
		    -value=>$outputcookiecontent,
		    -expires=>($deletecookie ? '-1h' : '+1h'));
  push @outputcookies, $cookie;
} 
#
# We also send back a debug cookie
#
#
if (defined($outputdebugcookiecontent)) { 
  my $cookie=cookie(-name=>$debugcookiename,
		    -value=>$outputdebugcookiecontent);
  push @outputcookies, $cookie;
}

#
# Headers and cookies sent back to client
#
# The page immediately expires so that it will be refetched if the
# client ever needs to update it
#
print header(-expires=>'now', -cookie=>\@outputcookies);

#
# Now we finally begin generating back HTML
#
#
#print start_html('Red, White, and Blue');
print "<html style=\"height: 100\%\">";
print "<head>";
print "<title>Financial Portfolio</title>";
print "</head>";

print "<body style=\"height:100\%;margin:0\">";

#
# Force device width, for mobile phones, etc
#
#print "<meta name=\"viewport\" content=\"width=device-width\" />\n";

# This tells the web browser to render the page in the style
# defined in the css file
#
print "<style type=\"text/css\">\n\@import \"rwb.css\";\n</style>\n";
 

print "<center>" if !$debug;


#
#
# The remainder here is essentially a giant switch statement based
# on $action. 
#
#
#


# LOGIN
#
# Login is a special case since we handled running the filled out form up above
# in the cookie-handling code.  So, here we only show the form if needed
# 
#
if ($action eq "login") { 
  if ($logincomplain) { 
    print "Login failed.  Try again.<p>"
  } 
  if ($logincomplain or !$run) { 
    print start_form(-name=>'Login'),
      h2('Login to Financial Portfolio'),
	"Username:",textfield(-name=>'username'),p,
	  "Password:",password_field(-name=>'password'),p,
	    hidden(-name=>'act',default=>['login']),
	      hidden(-name=>'run',default=>['1']),
		submit,
		  end_form;
  }
}



#
# BASE
#
# The base action presents the overall page to the browser
# This is the "document" that the JavaScript manipulates
#
#
if ($action eq "base") { 
  #
  # The Javascript portion of our app
  #
  print "<script type=\"text/javascript\" src=\"rwb.js\"> </script>";



  if ($debug) {
    # visible if we are debugging
    print "<div id=\"data\" style=\:width:100\%; height:10\%\"></div>";
  } else {
    # invisible otherwise
    print "<div id=\"data\" style=\"display: none;\"></div>";
  }


# height=1024 width=1024 id=\"info\" name=\"info\" onload=\"UpdateMap()\"></iframe>";
  

  #
  # User mods
  #
  #
if(UserCan($user, "query-fec-data")){
  print "<table border='0' style='text-align:center'><tr>";
  if(UserCan($user, "query-opinion-data")){
	print "<td><input type='checkbox' id='opinion_checkbox'><strong> Opinions</strong></input></td>";
  }
  print "<td><input type='checkbox' id='committee_checkbox'><strong> Committee</strong></input></td>
         <td><strong><input type='checkbox' id='candidate_checkbox'> Candidate</input></strong></td>
         <td><strong><input type='checkbox' id='individual_checkbox'> Individual</strong></input><br></td>";
  print "</tr></table>";
  print "<table style='text-align:center'>";
  print "<tr>";
  print "<td><input type='checkbox' id='8182' class='cycle_num'>1981-1982</input></td>
        <td><input type='checkbox' id='8283' class='cycle_num'>1982-1983</input></td>
        <td><input type='checkbox' id='8384' class='cycle_num'>1983-1984</input></td>
        <td><input type='checkbox' id='8485' class='cycle_num'>1984-1985</input></td>
        <td><input type='checkbox' id='8586' class='cycle_num'>1985-1986</input></td>
        <td><input type='checkbox' id='8687' class='cycle_num'>1986-1987</input></td>";
  print "</tr>";
  print "<tr>";
  print "<td><input type='checkbox' id='8788' class='cycle_num'>1987-1988</input></td>
        <td><input type='checkbox' id='8889' class='cycle_num'>1988-1989</input></td>
        <td><input type='checkbox' id='8990' class='cycle_num'>1989-1990</input></td>
        <td><input type='checkbox' id='9091' class='cycle_num'>1990-1991</input></td>
        <td><input type='checkbox' id='9192' class='cycle_num'>1991-1992</input></td>
        <td><input type='checkbox' id='9293' class='cycle_num'>1992-1993</input></td>";
  print "</tr>";
  print "<tr>";
  print "<td><input type='checkbox' id='9394' class='cycle_num'>1993-1994</input></td>
        <td><input type='checkbox' id='9495' class='cycle_num'>1994-1995</input></td>
        <td><input type='checkbox' id='9596' class='cycle_num'>1995-1996</input></td>
        <td><input type='checkbox' id='9697' class='cycle_num'>1996-1997</input></td>
        <td><input type='checkbox' id='9798' class='cycle_num'>1997-1998</input></td>
        <td><input type='checkbox' id='9899' class='cycle_num'>1998-1999</input></td>";
  print "</tr>";
  print "<tr>";
  print "<td><input type='checkbox' id='9900' class='cycle_num'>1999-2000</input></td>
        <td><input type='checkbox' id='0001' class='cycle_num'>2000-2001</input></td>
        <td><input type='checkbox' id='0102' class='cycle_num'>2001-2002</input></td>
        <td><input type='checkbox' id='0203' class='cycle_num'>2002-2003</input></td>
        <td><input type='checkbox' id='0304' class='cycle_num'>2003-2004</input></td>
        <td><input type='checkbox' id='0405' class='cycle_num'>2004-2005</input></td>";
  print "</tr>";
  print "<tr>";
  print "<td><input type='checkbox' id='0506' class='cycle_num'>2005-2006</input></td>
        <td><input type='checkbox' id='0607' class='cycle_num'>2006-2007</input></td>
        <td><input type='checkbox' id='0708' class='cycle_num'>2007-2008</input></td>
        <td><input type='checkbox' id='0809' class='cycle_num'>2008-2009</input></td>
        <td><input type='checkbox' id='0910' class='cycle_num'>2009-2010</input></td>
        <td><input type='checkbox' id='1011' class='cycle_num'>2010-2011</input></td>";
  print "</tr>";
  print "<tr>";
  print "<td><input type='checkbox' id='1112' class='cycle_num'>2011-2012</input></td>
        <td><input type='checkbox' id='1213' class='cycle_num'>2012-2013</input></td>
        <td><input type='checkbox' id='1314' class='cycle_num'>2013-2014</input></td>";
  print "</tr>";
  print "</table>";
}
print "<div id=\"comm_contributions\" style=\"background-color:white\">
                <h2>Committee Contributions</h2>
                <h4>Democratic:</h4>
                <p id=\"dem_contributions\">n/a</p>
                <h4>Republican:</h4>
                <p id=\"rep_contributions\">n/a</p>
         </div>";
  if ($user eq "anon") {
    print "<p>You are anonymous, but you can also <a href=\"rwb.pl?act=login\">login</a></p>";
  } else {
    print "<p>You are logged in as $user and can do the following:</p>";
    print "<table style='text-align: center'>";
    print "<tr>";
    if (UserCan($user,"give-opinion-data")) {
      print "<td><a href='rwb.pl?act=give-opinion-data'>Give Opinion Of Current Location</a></td>";
    }
    if (UserCan($user,"give-cs-ind-data")) {
      print "<td><a href=\"rwb.pl?act=give-cs-ind-data\">Geolocate Individual Contributors</a></td>";
    }
    if (UserCan($user,"manage-users") || UserCan($user,"invite-users")) {
      print "<td><a href=\"rwb.pl?act=invite-user\">Invite User</a></td>";
    }
    if (UserCan($user,"manage-users") || UserCan($user,"add-users")) { 
      print "<td><a href=\"rwb.pl?act=add-user\">Add User</a></td>";
    } 
    if (UserCan($user,"manage-users")) { 
      print "<td><a href=\"rwb.pl?act=delete-user\">Delete User</a></td>";
      print "<td><a href=\"rwb.pl?act=add-perm-user\">Add User Permission</a></td>";
      print "<td><a href=\"rwb.pl?act=revoke-perm-user\">Revoke User Permission</a></td>";
    }
    print "<tr></table>";
    print "<p></p>";
    print "<p><a href=\"rwb.pl?act=logout&run=1\">LOGOUT</a></p>";
  }

}

if ($action eq "aggreg") {
        my $latne = param("latne");
        my $longne = param("longne");
        my $latsw = param("latsw");
        my $longsw = param("longsw");
        my $whatparam = param("what");
        my $cycle = param("cycle");
        my %what;
        my @results;

        $cycle = "1314" if !defined($cycle);

        if (!defined($whatparam) || $whatparam eq "all") {
                %what = ( committees => 1,
                          candidates => 1,
                          individuals =>1,
                          opinions => 1);
        } else {
                map {$what{$_}=1} split(/\s*,\s*/,$whatparam);
        }

	if ($what{committees}) { 
		my (@results,$error) = CommitteeSum($latne,$longne,$latsw,$longsw,$cycle);
		if(!$error){
			print join "","|",$results[0],"|",$results[1],"|",$results[2],"|",$results[3],"|";
		}
	}
  

#	=begin comment
       # if ($what{candidates}) {
        #        my ($str,$error) = Candidates($latne,$longne,$latsw,$longsw,$cycle,$format);
         #       if (!$error) {
          #              if ($format eq "table") {
           #                     print "<h2>Nearby candidates</h2>$str";
            #            } else {
             #                   print $str;
              #          }
               # }
        #}

        #if ($what{individuals}) {
         #       my ($str,$error) = Individuals($latne,$longne,$latsw,$longsw,$cycle,$format);
          #      if (!$error) {
           #             if ($format eq "table") {
            #                    print "<h2>Nearby individuals</h2>$str";
 #                       } else {
  #                              print $str;
   #                     }
    #            }
     #   }       
      #  if ($what{opinions}) {
       #         my ($str,$error) = Opinions($latne,$longne,$latsw,$longsw,$cycle,$format);
        #        if (!$error) {
         #               if ($format eq "table") {
          #                      print "<h2>Nearby opinions</h2>$str";
           #             } else {
         #                       print $str;
          #              }
           #     }
#        }
#=end comment
#=cut
}
#
#
# NEAR
#
#
# Nearby committees, candidates, individuals, and opinions
#
#
# Note that the individual data should integrate the FEC data and the more
# precise crowd-sourced location data.   The opinion data is completely crowd-sourced
#
# This form intentionally avoids decoration since the expectation is that
# the client-side javascript will invoke it to get raw data for overlaying on the map
#
#
if ($action eq "near") {
  my $latne = param("latne");
  my $longne = param("longne");
  my $latsw = param("latsw");
  my $longsw = param("longsw");
  my $whatparam = param("what");
  my $format = param("format");
  my $cycle = param("cycle");
  my %what;
  
  $format = "table" if !defined($format);
  $cycle = "1314" if !defined($cycle);
  if (!defined($whatparam) || $whatparam eq "all") { 
    %what = ( committees => 1, 
	      candidates => 1,
	      individuals =>1,
	      opinions => 1);
  } else {
    map {$what{$_}=1} split(/\s*,\s*/,$whatparam);
  }
	       

  if ($what{committees}) { 
    my ($str,$error) = Committees($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby committees</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{candidates}) {
    my ($str,$error) = Candidates($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby candidates</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{individuals}) {
    my ($str,$error) = Individuals($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby individuals</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{opinions}) {
    my ($str,$error) = Opinions($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby opinions</h2>$str";
      } else {
	print $str;
      }
    }
  }

}

if($action eq "invitee_login"){
	if(!$run){
		print start_form(-name=>'InviteeLogin'),
		h2('Invitee First Time Login'),
		"Pick a username ", textfield(-name=>'name'),
		p,
		"Enter your email: ", textfield(-name=>'email'),
		p,
		"Enter your id: ", textfield(-name=>'id'),
		p,
		"Create Password: ", textfield(-name => 'password'),
		p,
		hidden(-name=>'run', -default=>['1']),
		hidden(-name=>'act', -default=>['invitee_login']),
		submit,
		end_form,
		hr;
	} else{
		my $name = param('name');
		my $email = param('email');
		my $id = param('id');
		my $password = param('password');
		my $erroradd;
		my $errordelin;
		my $errordelperm;
		if(CheckValidInvitee($name, $id)){
			$erroradd = UserAdd($name, $password, $email, $user);
			if($erroradd) { 
				if(index($erroradd, 'unique constraint') != -1){
					print "<p><strong><span style='color:red; font-size: 2em;'>Error!</span></strong></p><p>User is already in database.</p>";
				}
				elsif(index($erroradd, 'EMAIL_OK) violated') != -1){
					print "<p><strong><span style='color:red; font-size: 2em;'>Error!</span></strong></p><p>Email is not in the correct format. Be sure to include the @ sign.</p>";
				}
				elsif(index($erroradd, 'LONG_PASSWD) violated') != -1){
					print "<p><strong><span style='color:red; font-size: 2em;'>Error!</span></strong></p><p>Password must be at least 8 characters long.</p>";
				}
			}	
			else{
				my @perms = map{@$_}ExecSQL($dbuser, $dbpasswd, "select action from rwb_invitee_permissions where id=?",undef, $id); 
				for(my $j = 0; $j < @perms; $j+=1){
					my $dummy = GiveUserPerm($name, $perms[$j]);
					if($dummy) { print "$dummy";}
				}
				$errordelin = UserDelInvitee($id);
				$errordelperm = UserDelInviteePerm($id);
				if($errordelin){ print "<p>$errordelin</p>";}
				if($errordelperm) {print "<p>$errordelperm</p>";} 
				else{
					print "<p><strong><span style='color:green; font-size:2em;'>Success!</span></strong></pr><p>Added user $name at $email.</p>";
				}
			}
		}
		else { print "<p><strong><span style='color:red; font-size: 2em;'>Error!</span></strong></p><p>You have not been officially invited!</p><p>Please check that your name, email, and id are all correct.</p>";}

	}
	print "<p><a href='rwb.pl?act=base&run=1'>Return</a></p>";
}
if ($action eq "invite-user") { 
 if(!UserCan($user, "invite-users")){
 	print h2("You do not have the required permissions to invite users.");	
 }
 else{
	if(!$run){
		my @permissions = map{@$_}ExecSQL($dbuser, $dbpasswd, "select action from rwb_permissions where name=?", undef, $user);
		print start_form(-name=>'InviteUser'),
		  h2('Invite User'),
		    "Name: ", textfield(-name=>'name'),
		     p,
		       "Email: ", textfield(-name=>'email'),
			p,
			"Permissions? ",
			checkbox_group(-name => 'permissions',
					-values => \@permissions),
			  hidden(-name=>'run', -default=>['1']),
			  hidden(-name=>'act', -default=>['invite-user']),p,
			    submit,
			     end_form,
			       hr;
	}
	else{
		my $name = param('name');
		my $email = param('email');
		my @picked_perms = param('permissions');
		
 		my $id = join '', $name, $user, int(rand(10000000000));
		my $errorinvite;
		if(!ValidUserNoPass($name, $email)) {#not in database
			$errorinvite = UserInvite($name,$email,$id,$user);
			if($errorinvite){
				if(index($errorinvite, 'EMAIL_OK2) violated') != -1) {
					print "<p><strong><span style='color:red; font-size: 2em;'>Error!</span></strong></p><p>Email is not properly formatted.</p>";
				}
	
				elsif(index($errorinvite, 'unique constraint') != -1){
					print "<p><strong><span style='color:red; font-size: 2em;'>Error!</span></strong></p><p>User has already been invited.</p>";
				}
			}
			else {
				print "<p><strong><span style='color:green; font-size:2em;'>Success!</span></strong></pr><p>Added user $name at $email as referred to be $user.</p>";
				for(my $i=0; $i < @picked_perms; $i+=1){
					InsertInviteePermissions($name, $email, $id, $picked_perms[$i]);
					print "<p>Sucessfully added permission $picked_perms[$i]</p>";
				}
				print "<p>Invited user $name at $email as referred by $user</p>";
			}
		
		}
		else {
			print "<p><strong><span style='color:red; font-size: 2em;'>Error!</span></strong></p><p>User is already in database.</p>";

		}
	}
	print "<p><a href='rwb.pl?act=base&run=1'>Return</a></p>";
 }
}

if ($action eq "give-opinion-data") { 
	if(!UserCan($user, "give-opinion-data")){
		print h2("You do not have the required permissions to give opinion data");
	}
	else {
		if(!$run){
			print "<head>";
			print "<title>Give Opinion Data</title>";
			print "</head>";


			print "<body>";

			print "<script>";
			print "\nvar field1;";
			print "\nvar field2;";
			print "\nvar x;";
			print "\nfunction getLocation() {";
			print "\n  if (navigator.geolocation) {";
			print "        navigator.geolocation.getCurrentPosition(showPosition);";
			print "    } else {";
			print "        x.innerHTML = 'Geolocation is not supported by this browser.';";
			print    "} };\n";
			print "function showPosition(position){";
			print "   field1.value = position.coords.latitude;";
			print "   field2.value = position.coords.longitude;";
			print "};";

			print "\nwindow.onload = function() {";
			print "  field1 = document.getElementById('latfield');";
			print "  field2 = document.getElementById('longfield');";
			print "  var x = document.getElementById('demo');";
			print "  getLocation()";
			print "};\n";
			print "</script>\n";

			my %labels = (
				'-1' => 'Republican',
				'0' => 'Neutral',
				'1' => 'Democrat');
			print start_form(-name=>'GiveOpinionData'),
				h2('Give Opinion Data'),
					"Assign this location Republican or Democrat? ",p,
					radio_group(-name=>'opinions',
						-values=>['-1','0','1'],
						-labels=>\%labels),p,
					"Latitude: ", textfield(-name=>'lati', -id=>'latfield'),p,
					"Longitude: ", textfield(-name=>'longe', -id=>'longfield'),p,
					hidden(-name=>'run', -default=>['1']),
					hidden(-name=>'act', -default=>['give-opinion-data']),p,
					submit,
					end_form,
					hr;
		}
		else{
			my $opinion = param('opinions');
			my $lat = param("lati");
			my $long = param("longe");
			my $error = InsertOpinion($user, $opinion, $lat, $long);
			if ($error) { print "$error";}
			else { 
				print "<p><strong><span style='color:green; font-size:2em;'>Success!</span></strong></pr><p>Successfully added opinion.</p>";
			}
		}
	}
	print "<p><a href='rwb.pl?act=base&run=1'>Return</a></p>";
}

if ($action eq "give-cs-ind-data") { 
  print h2("Giving Crowd-sourced Individual Geolocations Is Unimplemented");

}




#
# ADD-USER
#
# User Add functionaltiy 
#
#
#
#
#
if ($action eq "add-user") { 
  if (!UserCan($user,"add-users") && !UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to add users.');
  } else {
    if (!$run) { 
      print start_form(-name=>'AddUser'),
	h2('Add User'),
	  "Name: ", textfield(-name=>'name'),
	    p,
	      "Email: ", textfield(-name=>'email'),
		p,
		  "Password: ", textfield(-name=>'password'),
		    p,
		      hidden(-name=>'run',-default=>['1']),
			hidden(-name=>'act',-default=>['add-user']),
			  submit,
			    end_form,
			      hr;
    } else {
      my $name=param('name');
      my $email=param('email');
      my $password=param('password');
      my $error;
      $error=UserAdd($name,$password,$email,$user);
      if ($error) { 
	print "Can't add user because: $error";
      } else {
	print "Added user $name $email as referred by $user\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}

#
# DELETE-USER
#
# User Delete functionaltiy 
#
#
#
#
if ($action eq "delete-user") { 
  if (!UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to delete users.');
  } else {
    if (!$run) { 
      #
      # Generate the add form.
      #
      print start_form(-name=>'DeleteUser'),
	h2('Delete User'),
	  "Name: ", textfield(-name=>'name'),
	    p,
	      hidden(-name=>'run',-default=>['1']),
		hidden(-name=>'act',-default=>['delete-user']),
		  submit,
		    end_form,
		      hr;
    } else {
      my $name=param('name');
      my $error;
      $error=UserDel($name);
      if ($error) { 
	print "Can't delete user because: $error";
      } else {
	print "Deleted user $name\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}


#
# ADD-PERM-USER
#
# User Add Permission functionaltiy 
#
#
#
#
if ($action eq "add-perm-user") { 
  if (!UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to manage user permissions.');
  } else {
    if (!$run) { 
      #
      # Generate the add form.
      #
      print start_form(-name=>'AddUserPerm'),
	h2('Add User Permission'),
	  "Name: ", textfield(-name=>'name'),
	    "Permission: ", textfield(-name=>'permission'),
	      p,
		hidden(-name=>'run',-default=>['1']),
		  hidden(-name=>'act',-default=>['add-perm-user']),
		  submit,
		    end_form,
		      hr;
      my ($table,$error);
      ($table,$error)=PermTable();
      if (!$error) { 
	print "<h2>Available Permissions</h2>$table";
      }
    } else {
      my $name=param('name');
      my $perm=param('permission');
      my $error=GiveUserPerm($name,$perm);
      if ($error) { 
	print "Can't add permission to user because: $error";
      } else {
	print "Gave user $name permission $perm\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}


#
# REVOKE-PERM-USER
#
# User Permission Revocation functionaltiy 
#
#
#
#
if ($action eq "revoke-perm-user") { 
  if (!UserCan($user,"manage-users")) { 
    print h2('You do not have the required permissions to manage user permissions.');
  } else {
    if (!$run) { 
      #
      # Generate the add form.
      #
      print start_form(-name=>'RevokeUserPerm'),
	h2('Revoke User Permission'),
	  "Name: ", textfield(-name=>'name'),
	    "Permission: ", textfield(-name=>'permission'),
	      p,
		hidden(-name=>'run',-default=>['1']),
		  hidden(-name=>'act',-default=>['revoke-perm-user']),
		  submit,
		    end_form,
		      hr;
      my ($table,$error);
      ($table,$error)=PermTable();
      if (!$error) { 
	print "<h2>Available Permissions</h2>$table";
      }
    } else {
      my $name=param('name');
      my $perm=param('permission');
      my $error=RevokeUserPerm($name,$perm);
      if ($error) { 
	print "Can't revoke permission from user because: $error";
      } else {
	print "Revoked user $name permission $perm\n";
      }
    }
  }
  print "<p><a href=\"rwb.pl?act=base&run=1\">Return</a></p>";
}



#
#
#
#
# Debugging output is the last thing we show, if it is set
#
#
#
#

print "</center>" if !$debug;

#
# Generate debugging output if anything is enabled.
#
#
if ($debug) {
  print hr, p, hr,p, h2('Debugging Output');
  print h3('Parameters');
  print "<menu>";
  print map { "<li>$_ => ".escapeHTML(param($_)) } param();
  print "</menu>";
  print h3('Cookies');
  print "<menu>";
  print map { "<li>$_ => ".escapeHTML(cookie($_))} cookie();
  print "</menu>";
  my $max= $#sqlinput>$#sqloutput ? $#sqlinput : $#sqloutput;
  print h3('SQL');
  print "<menu>";
  for (my $i=0;$i<=$max;$i++) { 
    print "<li><b>Input:</b> ".escapeHTML($sqlinput[$i]);
    print "<li><b>Output:</b> $sqloutput[$i]";
  }
  print "</menu>";
}

print end_html;

#
# The main line is finished at this point. 
# The remainder includes utilty and other functions
#


#
# Generate a table of nearby committees
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#


sub Committees {
	my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
	my @cycle_list = split /,/, $cycle;  

	my $c = "";
	for(my $i=0; $i < @cycle_list; $i += 1){
		$c = join "", $c, "?,";
	}
	$c = substr($c, 0, -1);
	my @rows;
	my $sql_statement = join "","select latitude, longitude, cmte_nm, cmte_pty_affiliation, cmte_st1, cmte_st2, cmte_city, cmte_st, cmte_zip, cycle from cs339.committee_master natural join cs339.cmte_id_to_geo where cycle in(",$c, ") and latitude>? and latitude<? and longitude>? and longitude<?"; 
  eval { 
   @rows = ExecSQL($dbuser, $dbpasswd, $sql_statement,undef,@cycle_list,$latsw,$latne,$longsw,$longne);
 };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") { 
      return (MakeTable("committee_data","2D",
			["latitude", "longitude", "name", "party", "street1", "street2", "city", "state", "zip"],
			@rows),$@);
    } else {
      return (MakeRaw("committee_data","2D",@rows),$@);
    }
  }
}

sub CommitteeSum {
        my ($latne,$longne,$latsw,$longsw,$cycle) = @_;
        my @cycle_list = split /,/, $cycle;
        my $cmte_ids_size = "";
        my $cycles_size = "";
        my @cmte_ids;
	my @dem_comm_sum;
	my @dem_cand_sum;
	my @rep_comm_sum;
	my @rep_cand_sum;
        for(my $i=0; $i < @cycle_list; $i += 1){
                $cycles_size = join "", $cycles_size, "?,";
        }

        $cycles_size = substr($cycles_size, 0, -1);

        my $cmte_id_sql = join "","select cmte_id from cs339.committee_master natural join cs339.cmte_id_to_geo where cycle in(",$cycles_size, ") and latitude>? and latitude<? and longitude>? and longitude<?";

        eval {
                @cmte_ids = map{@$_}ExecSQL($dbuser, $dbpasswd, $cmte_id_sql,undef,@cycle_list,$latsw,$latne,$longsw,$longne);
        };

        for(my $i=0; $i < @cmte_ids; $i += 1){
                $cmte_ids_size = join "", $cmte_ids_size, "?,";
        }
        $cmte_ids_size = substr($cmte_ids_size, 0, -1);

                my $dem_comm_sql = join "","select sum(transaction_amnt) from cs339.committee_master natural join cs339.comm_to_comm where cmte_id in(", $cmte_ids_size, ") and cmte_pty_affiliation in('d','dem','DEM','dem','DM')";
                my $dem_cand_sql = join "","select sum(transaction_amnt) from cs339.committee_master natural join cs339.comm_to_cand where cmte_id in(", $cmte_ids_size, ") and cmte_pty_affiliation in('d','dem','DEM','dem','DM')";
                my $rep_comm_sql = join "","select sum(transaction_amnt) from cs339.committee_master natural join cs339.comm_to_comm where cmte_id in(", $cmte_ids_size, ") and cmte_pty_affiliation in('R','Rep','REP','rep','GOP')";
                my $rep_cand_sql = join "","select sum(transaction_amnt) from cs339.committee_master natural join cs339.comm_to_cand where cmte_id in(", $cmte_ids_size, ") and cmte_pty_affiliation in('R','Rep','REP','rep','GOP')";
                eval {
                        @dem_comm_sum = map{@$_}ExecSQL($dbuser, $dbpasswd, $dem_comm_sql,undef,@cmte_ids);
                        @dem_cand_sum = map{@$_}ExecSQL($dbuser, $dbpasswd, $dem_cand_sql,undef,@cmte_ids);
                        @rep_comm_sum = map{@$_}ExecSQL($dbuser, $dbpasswd, $rep_comm_sql,undef,@cmte_ids);
                        @rep_cand_sum = map{@$_}ExecSQL($dbuser, $dbpasswd, $rep_cand_sql,undef,@cmte_ids);
                };
                if ($@) {
                        return (undef,$@);
                } else{

                        my @dem_money = ( @dem_comm_sum, @dem_cand_sum);
                        my @rep_money = ( @rep_comm_sum, @rep_cand_sum);
                        my @results = ( @dem_comm_sum, @dem_cand_sum, @rep_comm_sum, @rep_cand_sum );
                        return @results;
                }


}
#
# Generate a table of nearby candidates
# ($table|$raw,$error) = Committees(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Candidates {
  my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
  my @rows;
  eval {  
    @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, cand_name, cand_pty_affiliation, cand_st1, cand_st2, cand_city, cand_st, cand_zip from cs339.candidate_master natural join cs339.cand_id_to_geo where cycle=? and latitude>? and latitude<? and longitude>? and longitude<?",undef,$cycle,$latsw,$latne,$longsw,$longne);
  };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") {
      return (MakeTable("candidate_data", "2D",
                        ["latitude", "longitude", "name", "party", "street1", "street2", "city", "state", "zip"],                       
                        @rows),$@);
    } else { 
      return (MakeRaw("candidate_data","2D",@rows),$@);
    }
  }
}


#
# Generate a table of nearby individuals
#
# Note that the handout version does not integrate the crowd-sourced data
#
# ($table|$raw,$error) = Individuals(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Individuals {
  my ($latne,$longne,$latsw,$longsw,$cycle,$format) = @_;
  
  my @cycle_list = split /,/, $cycle;  
  my $c = "";
  for(my $i=0; $i < @cycle_list; $i += 1){
	$c = join "", $c, "?,";
  }
  $c = substr($c, 0, -1);
  my @rows;
  my $sql_statement = join "",  "select latitude, longitude, cmte_nm, cmte_pty_affiliation, cmte_st1, cmte_st2, cmte_city, cmte_st, cmte_zip, cycle from cs339.committee_master natural join cs339.cmte_id_to_geo where cycle in(",$c, ") and latitude>? and latitude<? and longitude>? and longitude<?"; 
  eval { 
   @rows = ExecSQL($dbuser, $dbpasswd, $sql_statement, undef, @cycle_list, $latsw,$latne,$longsw, $longne);
  };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") { 
      return (MakeTable("individual_data", "2D",
			["latitude", "longitude", "name", "city", "state", "zip", "employer", "amount"],
			@rows),$@);
    } else {
      return (MakeRaw("individual_data","2D",@rows),$@);
    }
  }
}


#
# Generate a table of nearby opinions
#
# ($table|$raw,$error) = Opinions(latne,longne,latsw,longsw,cycle,format)
# $error false on success, error string on failure
#
sub Opinions {
  my ($latne, $longne, $latsw, $longsw, $cycle,$format) = @_;
  my @rows;
  eval { 
    @rows = ExecSQL($dbuser, $dbpasswd, "select latitude, longitude, color from rwb_opinions where latitude>? and latitude<? and longitude>? and longitude<?",undef,$latsw,$latne,$longsw,$longne);
  };
  
  if ($@) { 
    return (undef,$@);
  } else {
    if ($format eq "table") { 
      return (MakeTable("opinion_data","2D",
			["latitude", "longitude", "name", "city", "state", "zip", "employer", "amount"],
			@rows),$@);
    } else {
      return (MakeRaw("opinion_data","2D",@rows),$@);
    }
  }
}


#
# Generate a table of available permissions
# ($table,$error) = PermTable()
# $error false on success, error string on failure
#
sub PermTable {
  my @rows;
  eval { @rows = ExecSQL($dbuser, $dbpasswd, "select action from rwb_actions"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("perm_table",
		      "2D",
		     ["Perm"],
		     @rows),$@);
  }
}

#
# Generate a table of users
# ($table,$error) = UserTable()
# $error false on success, error string on failure
#
sub UserTable {
  my @rows;
  eval { @rows = ExecSQL($dbuser, $dbpasswd, "select name, email from rwb_users order by name"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("user_table",
		      "2D",
		     ["Name", "Email"],
		     @rows),$@);
  }
}

#
# Generate a table of users and their permissions
# ($table,$error) = UserPermTable()
# $error false on success, error string on failure
#
sub UserPermTable {
  my @rows;
  eval { @rows = ExecSQL($dbuser, $dbpasswd, "select rwb_users.name, rwb_permissions.action from rwb_users, rwb_permissions where rwb_users.name=rwb_permissions.name order by rwb_users.name"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("userperm_table",
		      "2D",
		     ["Name", "Permission"],
		     @rows),$@);
  }
}

# PortfolioAdd($account_name, $portfolio_name, $cash)
sub PortfolioAdd {
  eval {ExecSQL($dbuser,$dbpasswd,
		"insert into portfolios (account_name, portfolio_name, cash) values (?,?,?)",undef,@_);};  
}

# PortfolioDrop($account_name, $portfolio_name)
sub PortfolioDrop {
  eval {ExecSQL($dbuser,$dbpassd,
		"delete from portfolios where account_name=? and portfolio_name=?",undef,@_);};
}

# StockAdd($account_name, $portfolio_name, $symbol, $volume)
sub StockAdd {
  eval {ExecSQL($dbuser,$dbpasswd,
		"insert into stock_holdings (account_name, portfolio_name, symbol, volume) values (?,?,?,?)",undef,@_);};
}

sub UserAdd { 
  eval { ExecSQL($dbuser,$dbpasswd,
		 "insert into rwb_users (name,password,email,referer) values (?,?,?,?)",undef,@_);};
  return $@;
}

sub InsertOpinion{
  
  eval { ExecSQL($dbuser,$dbpasswd,
		 "insert into rwb_opinions (submitter,color,latitude,longitude) values (?,?,?,?)",undef,@_);};
  return $@;
}

#InsertInvitee($name, $email, $user)
#helper function for UserInvite
sub InsertInvitee{
  
  eval { ExecSQL($dbuser,$dbpasswd,
		 "insert into rwb_invitees (name,id,email,referer) values (?,?,?,?)",undef,@_);};
  return $@;
}

sub InsertInviteePermissions{
  
  eval { ExecSQL($dbuser,$dbpasswd,
		 "insert into rwb_invitee_permissions (name,email,id,action) values (?,?,?,?)",undef,@_);};
  return $@;
}

sub CheckValidInvitee{
  my ($name,$id) = @_;
  my @col;
  eval {@col=ExecSQL($dbuser,$dbpasswd,"select count(*) from rwb_invitees where name=? and id=?", undef, $name, $id);};
  if($@) { return 0; }
  else { return $col[0] > 0; }
}



# UserInvite($name, $email, $user, @permissions)
sub UserInvite {
 my ($name,$email, $id, $user) = @_;
 my $link = 'http://murphy.wot.eecs.northwestern.edu/~jrp338/rwb/rwb/rwb.pl?act=invitee_login';

 my $body = join '','Congratulations, ', $name, '! You have been invited to RWB by ', $user,'. Please enter your id: ', $id,' at the following link to accept your invitation: ', $link;
 my $error = InsertInvitee($name, $id,$email, $user);
 if($error){ }
 else{
	open(MAIL, "| mail -s \"Invitation to RWB\" $email");
	print MAIL $body;
	close(MAIL);
 }
 return $@;
}




#
# Delete a user
# returns false on success, $error string on failure
# 
sub UserDel { 
  eval {ExecSQL($dbuser,$dbpasswd,"delete from rwb_users where name=?", undef, @_);};
  return $@;
}

sub UserDelInvitee{
  eval {ExecSQL($dbuser,$dbpasswd,"delete from rwb_invitees where id=?", undef, @_);};
  return $@;
}

sub UserDelInviteePerm{
  eval {ExecSQL($dbuser,$dbpasswd,"delete from rwb_invitee_permissions where id=?", undef, @_);};
  return $@;
}

#
# Give a user a permission
#
# returns false on success, error string on failure.
# 
# GiveUserPerm($name,$perm)
#
sub GiveUserPerm { 
  eval { ExecSQL($dbuser,$dbpasswd,
		 "insert into rwb_permissions (name,action) values (?,?)",undef,@_);};
  return $@;
}


#
# Revoke a user's permission
#
# returns false on success, error string on failure.
# 
# RevokeUserPerm($name,$perm)
#
sub RevokeUserPerm { 
  eval { ExecSQL($dbuser,$dbpasswd,
		 "delete from rwb_permissions where name=? and action=?",undef,@_);};
  return $@;
}

#
#
# Check to see if user and password combination exist
#
# $ok = ValidUser($user,$password)
#
#
sub ValidUser {
  my ($user,$email,$password)=@_;
  my @col;
  eval {@col=ExecSQL($dbuser,$dbpasswd, "select count(*) from rwb_users where name=? and email = ? and password=?","COL",$user,$email,$password);};
  if ($@) { 
    return 0;
  } else {
    return $col[0]>0;
  }
}
sub ValidUserNoPass {

  my ($user,$email)=@_;
  my @col;
  eval {@col=ExecSQL($dbuser,$dbpasswd, "select count(*) from rwb_users where name=? and email = ?","COL",$user,$email);};
  if ($@) { 
    return 0;
  } else {
    return $col[0]>0;
  }
}

#
#
# Check to see if user can do some action
#
# $ok = UserCan($user,$action)
#
sub UserCan {
  my ($user,$action)=@_;
  my @col;
  eval {@col= ExecSQL($dbuser,$dbpasswd, "select count(*) from rwb_permissions where name=? and action=?","COL",$user,$action);};
  if ($@) { 
    return 0;
  } else {
    return $col[0]>0;
  }
}





#
# Given a list of scalars, or a list of references to lists, generates
# an html table
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
# $headerlistref points to a list of header columns
#
#
# $html = MakeTable($id, $type, $headerlistref,@list);
#
sub MakeTable {
  my ($id,$type,$headerlistref,@list)=@_;
  my $out;
  #
  # Check to see if there is anything to output
  #
  if ((defined $headerlistref) || ($#list>=0)) {
    # if there is, begin a table
    #
    $out="<table id=\"$id\" border>";
    #
    # if there is a header list, then output it in bold
    #
    if (defined $headerlistref) { 
      $out.="<tr>".join("",(map {"<td><b>$_</b></td>"} @{$headerlistref}))."</tr>";
    }
    #
    # If it's a single row, just output it in an obvious way
    #
    if ($type eq "ROW") { 
      #
      # map {code} @list means "apply this code to every member of the list
      # and return the modified list.  $_ is the current list member
      #
      $out.="<tr>".(map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>" } @list)."</tr>";
    } elsif ($type eq "COL") { 
      #
      # ditto for a single column
      #
      $out.=join("",map {defined($_) ? "<tr><td>$_</td></tr>" : "<tr><td>(null)</td></tr>"} @list);
    } else { 
      #
      # For a 2D table, it's a bit more complicated...
      #
      $out.= join("",map {"<tr>$_</tr>"} (map {join("",map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>"} @{$_})} @list));
    }
    $out.="</table>";
  } else {
    # if no header row or list, then just say none.
    $out.="(none)";
  }
  return $out;
}


#
# Given a list of scalars, or a list of references to lists, generates
# an HTML <pre> section, one line per row, columns are tab-deliminted
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
#
# $html = MakeRaw($id, $type, @list);
#
sub MakeRaw {
  my ($id, $type,@list)=@_;
  my $out;
  #
  # Check to see if there is anything to output
  #
  $out="<pre id=\"$id\">\n";
  #
  # If it's a single row, just output it in an obvious way
  #
  if ($type eq "ROW") { 
    #
    # map {code} @list means "apply this code to every member of the list
    # and return the modified list.  $_ is the current list member
    #
    $out.=join("\t",map { defined($_) ? $_ : "(null)" } @list);
    $out.="\n";
  } elsif ($type eq "COL") { 
    #
    # ditto for a single column
    #
    $out.=join("\n",map { defined($_) ? $_ : "(null)" } @list);
    $out.="\n";
  } else {
    #
    # For a 2D table
    #
    foreach my $r (@list) { 
      $out.= join("\t", map { defined($_) ? $_ : "(null)" } @{$r});
      $out.="\n";
    }
  }
  $out.="</pre>\n";
  return $out;
}

#
# @list=ExecSQL($user, $password, $querystring, $type, @fill);
#
# Executes a SQL statement.  If $type is "ROW", returns first row in list
# if $type is "COL" returns first column.  Otherwise, returns
# the whole result table as a list of references to row lists.
# @fill are the fillers for positional parameters in $querystring
#
# ExecSQL executes "die" on failure.
#
sub ExecSQL {
  my ($user, $passwd, $querystring, $type, @fill) =@_;
  if ($debug) { 
    # if we are recording inputs, just push the query string and fill list onto the 
    # global sqlinput list
    push @sqlinput, "$querystring (".join(",",map {"'$_'"} @fill).")";
  }
  my $dbh = DBI->connect("DBI:Oracle:",$user,$passwd);
  if (not $dbh) { 
    # if the connect failed, record the reason to the sqloutput list (if set)
    # and then die.
    if ($debug) { 
      push @sqloutput, "<b>ERROR: Can't connect to the database because of ".$DBI::errstr."</b>";
    }
    die "Can't connect to database because of ".$DBI::errstr;
  }
  my $sth = $dbh->prepare($querystring);
  if (not $sth) { 
    #
    # If prepare failed, then record reason to sqloutput and then die
    #
    if ($debug) { 
      push @sqloutput, "<b>ERROR: Can't prepare '$querystring' because of ".$DBI::errstr."</b>";
    }
    my $errstr="Can't prepare $querystring because of ".$DBI::errstr;
    $dbh->disconnect();
    die $errstr;
  }
  if (not $sth->execute(@fill)) { 
    #
    # if exec failed, record to sqlout and die.
    if ($debug) { 
      push @sqloutput, "<b>ERROR: Can't execute '$querystring' with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr."</b>";
    }
    my $errstr="Can't execute $querystring with fill (".join(",",map {"'$_'"} @fill).") because of ".$DBI::errstr;
    $dbh->disconnect();
    die $errstr;
  }
  #
  # The rest assumes that the data will be forthcoming.
  #
  #
  my @data;
  if (defined $type and $type eq "ROW") { 
    @data=$sth->fetchrow_array();
    $sth->finish();
    if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","ROW",undef,@data);}
    $dbh->disconnect();
    return @data;
  }
  my @ret;
  while (@data=$sth->fetchrow_array()) {
    push @ret, [@data];
  }
  if (defined $type and $type eq "COL") { 
    @data = map {$_->[0]} @ret;
    $sth->finish();
    if ($debug) {push @sqloutput, MakeTable("debug_sqloutput","COL",undef,@data);}
    $dbh->disconnect();
    return @data;
  }
  $sth->finish();
  if ($debug) {push @sqloutput, MakeTable("debug_sql_output","2D",undef,@ret);}
  $dbh->disconnect();
  return @ret;
}


######################################################################
#
# Nothing important after this
#
######################################################################

# The following is necessary so that DBD::Oracle can
# find its butt
#
BEGIN {
  unless ($ENV{BEGIN_BLOCK}) {
    use Cwd;
    $ENV{ORACLE_BASE}="/raid/oracle11g/app/oracle/product/11.2.0.1.0";
    $ENV{ORACLE_HOME}=$ENV{ORACLE_BASE}."/db_1";
    $ENV{ORACLE_SID}="CS339";
    $ENV{LD_LIBRARY_PATH}=$ENV{ORACLE_HOME}."/lib";
    $ENV{BEGIN_BLOCK} = 1;
    exec 'env',cwd().'/'.$0,@ARGV;
  }
}

