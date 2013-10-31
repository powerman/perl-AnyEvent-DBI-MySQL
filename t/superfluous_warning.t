#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use AnyEvent::DBI::MySQL;


chomp(my ($db, $login, $pass) = `cat t/.answers`);

if ($db eq q{}) {
    plan skip_all => 'No database provided for testing';
} 


local *STDERR;
open STDERR, '>', \my $stderr or die $!;
# failed connect (because of wrong port 3307) will add undefined $dbh into {CachedKids}
AnyEvent::DBI::MySQL->connect("dbi:mysql:host=127.0.0.1;port=3307;database=$db",
    $login, $pass, {RaiseError=>0,PrintError=>0});
# passed connect shouldn't print warnings because of undefined $dbh in {CachedKids}
AnyEvent::DBI::MySQL->connect("dbi:mysql:host=127.0.0.1;port=3306;database=$db",
    $login, $pass, {RaiseError=>0,PrintError=>0});
is $stderr, undef, 'no warnings';


done_testing();
