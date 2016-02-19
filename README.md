[![Build Status](https://travis-ci.org/powerman/perl-AnyEvent-DBI-MySQL.svg?branch=master)](https://travis-ci.org/powerman/perl-AnyEvent-DBI-MySQL)
[![Coverage Status](https://coveralls.io/repos/powerman/perl-AnyEvent-DBI-MySQL/badge.svg?branch=master)](https://coveralls.io/r/powerman/perl-AnyEvent-DBI-MySQL?branch=master)

# NAME

AnyEvent::DBI::MySQL - Asynchronous MySQL queries

# VERSION

This document describes AnyEvent::DBI::MySQL version v1.0.6

# SYNOPSIS

    use AnyEvent::DBI::MySQL;

    # get cached but not in use $dbh
    $dbh = AnyEvent::DBI::MySQL->connect(…);

    # async
    $dbh->do(…,                 sub { my ($rv, $dbh) = @_; … });
    $sth = $dbh->prepare(…);
    $sth->execute(…,            sub { my ($rv, $sth) = @_; … });
    $dbh->selectall_arrayref(…, sub { my ($ary_ref)  = @_; … });
    $dbh->selectall_hashref(…,  sub { my ($hash_ref) = @_; … });
    $dbh->selectcol_arrayref(…, sub { my ($ary_ref)  = @_; … });
    $dbh->selectrow_array(…,    sub { my (@row_ary)  = @_; … });
    $dbh->selectrow_arrayref(…, sub { my ($ary_ref)  = @_; … });
    $dbh->selectrow_hashref(…,  sub { my ($hash_ref) = @_; … });

    # sync
    $rv = $dbh->do('…');
    $dbh->do('…', {async=>0}, sub { my ($rv, $dbh) = @_; … });

# DESCRIPTION

This module is an [AnyEvent](https://metacpan.org/pod/AnyEvent) user, you need to make sure that you use and
run a supported event loop.

This module implements asynchronous MySQL queries using
["ASYNCHRONOUS QUERIES" in DBD::mysql](https://metacpan.org/pod/DBD::mysql#ASYNCHRONOUS-QUERIES) feature. Unlike [AnyEvent::DBI](https://metacpan.org/pod/AnyEvent::DBI) it
doesn't spawn any processes.

You shouldn't use `{RaiseError=>1}` with this module and should check
returned values in your callback to detect errors. This is because with
`{RaiseError=>1}` exception will be thrown **instead** of calling your
callback function, which isn't what you want in most cases.

# INTERFACE 

The API is trivial: use it just like usual DBI, but instead of expecting
return value from functions which may block add one extra parameter: callback.
That callback will be executed with usual returned value of used method in
params (only exception is extra $dbh/$sth param in do() and execute() for
convenience).

## SYNCHRONOUS QUERIES

In most cases to make usual synchronous query it's enough to don't provide
callback - use standard DBI params and it will work just like usual DBI.
Only exception is prepare()/execute() pair: you should use
`{async=>0}` attribute for prepare() to have synchronous execute().

For convenience, you can quickly turn asynchronous query to synchronous by
adding `{async=>0}` attribute - you don't have to rewrite code to
remove callback function. In this case your callback will be called
immediately after executing this synchronous query.

- connect(…)

    [DBD::mysql](https://metacpan.org/pod/DBD::mysql) support only single asynchronous query per MySQL connection.
    To make it easier to overcome this limitation provided connect()
    constructor work using DBI->connect\_cached() under the hood, but it reuse
    only inactive $dbh - i.e. one which you didn't use anymore. So, connect()
    guarantee to not return $dbh which is already in use in your code.
    For example, in FastCGI or Mojolicious app you can safely use connect() to
    get own $dbh per each incoming connection; after you send response and
    close this connection that $dbh should automatically go out of scope and
    become inactive (you can force this by `$dbh=undef;`); after that this
    $dbh may be returned by connect() when handling next incoming request.
    As result you should automatically get a pool of connected $dbh which size
    should match peak amount of simultaneously handled CGI requests.
    You can flush that $dbh cache as documented by [DBI](https://metacpan.org/pod/DBI) at any time.

    NOTE: To implement this caching behavior this module catch DESTROY() for
    $dbh and instead of destroying it (and calling $dbh->disconnect()) make it
    available for next connect() call in cache. So, if you need to call
    $dbh->disconnect() - do it manually and don't expect it to happens
    automatically on $dbh DESTROY(), like it work in DBI.

    Also, usual limitations for cached connections apply as documented by
    [DBI](https://metacpan.org/pod/DBI) (read: don't change $dbh configuration).

- $dbh->do(…, sub { my ($rv, $dbh) = @\_; … });
- $sth->execute(…, sub { my ($rv, $sth) = @\_; … });
- $dbh->selectall\_arrayref(…, sub { my ($ary\_ref) = @\_; … });
- $dbh->selectall\_hashref(…, sub { my ($hash\_ref) = @\_; … });
- $dbh->selectcol\_arrayref(…, sub { my ($ary\_ref) = @\_; … });
- $dbh->selectrow\_array(…, sub { my (@row\_ary) = @\_; … });
- $dbh->selectrow\_arrayref(…, sub { my ($ary\_ref) = @\_; … });
- $dbh->selectrow\_hashref(…, sub { my ($hash\_ref) = @\_; … });

# BUGS AND LIMITATIONS

No bugs have been reported.

These DBI methods not supported yet (i.e. they work as usually - in
blocking mode), mostly because they internally run several queries and
should be completely rewritten to support non-blocking mode.

NOTE: You have to provide `{async=>0}` attribute to prepare() before
using execute\_array() or execute\_for\_fetch().

    $sth->execute_array(…)
    $sth->execute_for_fetch(…)
    $dbh->table_info(…)
    $dbh->column_info(…)
    $dbh->primary_key_info(…)
    $dbh->foreign_key_info(…)
    $dbh->statistics_info(…)
    $dbh->primary_key(…)
    $dbh->tables(…)

# SEE ALSO

[AnyEvent](https://metacpan.org/pod/AnyEvent), [DBI](https://metacpan.org/pod/DBI), [AnyEvent::DBI](https://metacpan.org/pod/AnyEvent::DBI)

# SUPPORT

## Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at [https://github.com/powerman/perl-AnyEvent-DBI-MySQL/issues](https://github.com/powerman/perl-AnyEvent-DBI-MySQL/issues).
You will be notified automatically of any progress on your issue.

## Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.
Feel free to fork the repository and submit pull requests.

[https://github.com/powerman/perl-AnyEvent-DBI-MySQL](https://github.com/powerman/perl-AnyEvent-DBI-MySQL)

    git clone https://github.com/powerman/perl-AnyEvent-DBI-MySQL.git

## Resources

- MetaCPAN Search

    [https://metacpan.org/search?q=AnyEvent-DBI-MySQL](https://metacpan.org/search?q=AnyEvent-DBI-MySQL)

- CPAN Ratings

    [http://cpanratings.perl.org/dist/AnyEvent-DBI-MySQL](http://cpanratings.perl.org/dist/AnyEvent-DBI-MySQL)

- AnnoCPAN: Annotated CPAN documentation

    [http://annocpan.org/dist/AnyEvent-DBI-MySQL](http://annocpan.org/dist/AnyEvent-DBI-MySQL)

- CPAN Testers Matrix

    [http://matrix.cpantesters.org/?dist=AnyEvent-DBI-MySQL](http://matrix.cpantesters.org/?dist=AnyEvent-DBI-MySQL)

- CPANTS: A CPAN Testing Service (Kwalitee)

    [http://cpants.cpanauthors.org/dist/AnyEvent-DBI-MySQL](http://cpants.cpanauthors.org/dist/AnyEvent-DBI-MySQL)

# AUTHOR

Alex Efros &lt;powerman@cpan.org>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2013-2014 by Alex Efros &lt;powerman@cpan.org>.

This is free software, licensed under:

    The MIT (X11) License
