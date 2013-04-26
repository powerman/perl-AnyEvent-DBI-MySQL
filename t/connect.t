#!/usr/bin/perl
use warnings;
use strict;
use Test::More;

use AnyEvent::DBI::MySQL;


chomp(my ($db, $login, $pass) = `cat t/.answers`);

if ($db eq q{}) {
    plan skip_all => 'No database provided for testing';
} else {
    plan tests => 11;
}


sub _connect { AnyEvent::DBI::MySQL->connect('dbi:mysql:'.$db, $login, $pass) }

my $dbh1 = _connect();
ok($dbh1, 'connected');
is(ref $dbh1, 'AnyEvent::DBI::MySQL::db', 'class');

my $dbh2 = _connect();
isnt($dbh1, $dbh2, 'new connection');

my $dbh3 = _connect();
isnt($dbh1, $dbh3, 'new connection');
isnt($dbh2, $dbh3, 'new connection');

my $addr1 = "$dbh1";
my $addr2 = "$dbh2";
my $addr3 = "$dbh3";

$dbh2 = undef;
$dbh2 = _connect();
isnt($dbh1, $dbh2, 'new connection');
isnt($dbh3, $dbh2, 'new connection');

is($addr2, "$dbh2", 'reused');

$dbh3 = undef;
$dbh1 = undef;
$dbh1 = _connect();
$dbh3 = _connect();
is($addr1, "$dbh1", 'reused');
is($addr3, "$dbh3", 'reused');

$dbh1->disconnect();
# $dbh1 = undef;
$dbh1 = _connect();
isnt($addr1, "$dbh1", 'not reused');


done_testing();
