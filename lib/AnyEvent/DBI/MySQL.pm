package AnyEvent::DBI::MySQL;

use warnings;
use strict;
use utf8;
use feature ':5.10';
use Carp;

use version; our $VERSION = qv('1.0.0');    # REMINDER: update Changes

## no critic(ProhibitMultiplePackages Capitalization ProhibitNoWarnings)

# REMINDER: update dependencies in Build.PL
use base qw( DBI );
use AnyEvent;
use Scalar::Util qw( weaken );

my @DATA;
my @NEXT_ID = ();
my $NEXT_ID = 0;
my $PRIVATE = 'private_' . __PACKAGE__;
my $PRIVATE_async = "$PRIVATE/async";

# Force connect_cached() but with unique key in $attr - this guarantee
# cached $dbh will be reused only after they no longer in use by user.
# Use {RootClass} instead of $class->connect_cached() because
# DBI->connect_cached() will call $class->connect() in turn.
sub connect { ## no critic(ProhibitBuiltinHomonyms)
    my ($class, $dsn, $user, $pass, $attr) = @_;
    local $SIG{__WARN__} = sub { (my $msg=shift)=~s/ at .*//ms; carp $msg };
    my $id = @NEXT_ID ? pop @NEXT_ID : $NEXT_ID++;

    $attr //= {};
    $attr->{RootClass} = $class;
    $attr->{$PRIVATE} = $id;
    my $dbh = DBI->connect_cached($dsn, $user, $pass, $attr);

    # weaken cached $dbh to have DESTROY called when user stop using it
    my $cache = $dbh->{Driver}{CachedKids};
    for (grep {$cache->{$_} == $dbh} keys %{$cache}) {
        weaken($cache->{$_});
    }

    $DATA[ $id ] = {
        io => AnyEvent->io(
            fh      => $dbh->mysql_fd,
            poll    => 'r',
            cb      => sub {
                local $SIG{__WARN__} = sub { (my $msg=shift)=~s/ at .*//ms; warn "$msg\n" };
                my $data = $DATA[$id];
                my $cb = delete $data->{cb};
                my $h  = delete $data->{h};
                my $args=delete $data->{call_again};
                if ($cb && $h) {
                    $cb->( $h->mysql_async_result, $h, $args );
                }
            },
        ),
    };

    return $dbh;
}


package AnyEvent::DBI::MySQL::db;
use base qw( DBI::db );
use Carp;
use Scalar::Util qw( weaken );

my $GLOBAL_DESTRUCT = 0;
END { $GLOBAL_DESTRUCT = 1; }

sub DESTROY {
    my ($dbh) = @_;

    if ($GLOBAL_DESTRUCT) {
        return $dbh->SUPER::DESTROY();
    }

    $DATA[ $dbh->{$PRIVATE} ] = {};
    push @NEXT_ID, $dbh->{$PRIVATE};
    if (!$dbh->{Active}) {
        $dbh->SUPER::DESTROY();
    }
    else {
        # un-weaken cached $dbh to keep it for next connect_cached()
        my $cache = $dbh->{Driver}{CachedKids};
        for (grep {$cache->{$_} && $cache->{$_} == $dbh} keys %{$cache}) {
            $cache->{$_} = $dbh;
        }
    }
    return;
}

sub do { ## no critic(ProhibitBuiltinHomonyms)
    my ($dbh, @args) = @_;
    local $SIG{__WARN__} = sub { (my $msg=shift)=~s/ at .*//ms; carp $msg };
    if (ref $args[-1] eq 'CODE') {
        my $data = $DATA[ $dbh->{$PRIVATE} ];
        if ($data->{cb}) {
            croak q{can't make more than one asynchronous query simultaneously};
        }
        $data->{cb} = pop @args;
        $data->{h} = $dbh;
        weaken($data->{h});
        $args[1] //= {};
        $args[1]->{async} //= 1;
        if (!$args[1]->{async}) {
            my $cb = delete $data->{cb};
            my $h  = delete $data->{h};
            $cb->( $dbh->SUPER::do(@args), $h );
            return;
        }
    }
    else {
        $args[1] //= {};
        if ($args[1]->{async}) {
            croak q{callback required};
        }
    }
    return $dbh->SUPER::do(@args);
}

sub prepare {
    my ($dbh, @args) = @_;
    local $SIG{__WARN__} = sub { (my $msg=shift)=~s/ at .*//ms; carp $msg };
    $args[1] //= {};
    $args[1]->{async} //= 1;
    my $sth = $dbh->SUPER::prepare(@args) or return;
    $sth->{$PRIVATE} = $dbh->{$PRIVATE};
    $sth->{$PRIVATE_async} = $args[1]->{async};
    return $sth;
}

{   # replace C implementations in Driver.xst because it doesn't play nicely with DBI subclassing
    no warnings 'redefine';
    *DBI::db::selectrow_array   = \&DBD::_::db::selectrow_array;
    *DBI::db::selectrow_arrayref= \&DBD::_::db::selectrow_arrayref;
    *DBI::db::selectall_arrayref= \&DBD::_::db::selectall_arrayref;
}

my @methods = qw(
    selectcol_arrayref
    selectrow_hashref
    selectall_hashref
    selectrow_array
    selectrow_arrayref
    selectall_arrayref
);
for (@methods) {
    my $method = $_;
    my $super = "SUPER::$method";
    no strict 'refs';
    *{$method} = sub {
        my ($dbh, @args) = @_;
        local $SIG{__WARN__} = sub { (my $msg=shift)=~s/ at .*//ms; carp $msg };

        my $attr_idx = $method eq 'selectall_hashref' ? 2 : 1;
        if (ref $args[$attr_idx] eq 'CODE') {
            splice @args, $attr_idx, 0, {};
        } else {
            $args[$attr_idx] //= {};
        }

        if (ref $args[-1] eq 'CODE') {
            my $cb = $args[-1];
            $DATA[ $dbh->{$PRIVATE} ]->{call_again} = [@args[1 .. $#args-1]];
            weaken($dbh);
            $args[-1] = sub {
                my (undef, $sth, $args) = @_;
                return if !$dbh;
                bless $sth, 'AnyEvent::DBI::MySQL::st::ready';
                $cb->( $dbh->$super($sth, @{$args}) );
            };
        }
        else {
            if ($args[$attr_idx]->{async}) {
                croak q{callback required};
            } else {
                $args[$attr_idx]->{async} = 0;
            }
        }

        return $dbh->$super(@args);
    };
}


package AnyEvent::DBI::MySQL::st;
use base qw( DBI::st );
use Carp;
use Scalar::Util qw( weaken );

sub execute {
    my ($sth, @args) = @_;
    local $SIG{__WARN__} = sub { (my $msg=shift)=~s/ at .*//ms; carp $msg };
    my $data = $DATA[ $sth->{$PRIVATE} ];
    if (ref $args[-1] eq 'CODE') {
        if ($data->{cb}) {
            croak q{can't make more than one asynchronous query simultaneously};
        }
        $data->{cb} = pop @args;
        $data->{h} = $sth;
        if ($data->{call_again}) {
            $sth->SUPER::execute(@args);
            # The select*() functions should be called twice:
            # - first time they'll do only prepare() and execute()
            #   * we should return false here to interrupt them after
            #     execute(), before they'll start fetching data
            #   * we shouldn't weaken {h} because their $sth will be
            #     destroyed when they will be interrupted
            # - second time they'll do only data fetching:
            #   * they should get ready $sth instead of query param,
            #     so they'll skip prepare()
            #   * this $sth should be AnyEvent::DBI::MySQL::st::ready,
            #     so they'll skip execute()
            return;
        }
        if (!$sth->{$PRIVATE_async}) {
            my $cb = delete $data->{cb};
            my $h  = delete $data->{h};
            $cb->( $sth->SUPER::execute(@args), $h );
            return;
        }
    }
    elsif ($sth->{$PRIVATE_async}) {
        croak q{callback required};
    }
    return $sth->SUPER::execute(@args);
}


package AnyEvent::DBI::MySQL::st::ready;
use base qw( DBI::st );
sub execute { return '0E0' };


1; # Magic true value required at end of module
__END__

=encoding utf8

=head1 NAME

AnyEvent::DBI::MySQL - Asynchronous MySQL queries


=head1 SYNOPSIS

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


=head1 DESCRIPTION

This module is an L<AnyEvent> user, you need to make sure that you use and
run a supported event loop.

This module implements asynchronous MySQL queries using
L<DBD::mysql/"ASYNCHRONOUS QUERIES"> feature. Unlike L<AnyEvent::DBI> it
doesn't spawn any processes.

You shouldn't use C<< {RaiseError=>1} >> with this module and should check
returned values in your callback to detect errors. This is because with
C<< {RaiseError=>1} >> exception will be thrown B<instead> of calling your
callback function, which isn't what you want in most cases.


=head1 INTERFACE 

The API is trivial: use it just like usual DBI, but instead of expecting
return value from functions which may block add one extra parameter: callback.
That callback will be executed with usual returned value of used method in
params (only exception is extra $dbh/$sth param in do() and execute() for
convenience).

=head2 SYNCHRONOUS QUERIES

In most cases to make usual synchronous query it's enough to don't provide
callback - use standard DBI params and it will work just like usual DBI.
Only exception is prepare()/execute() pair: you should use
C<< {async=>0} >> attribute for prepare() to have synchronous execute().

For convenience, you can quickly turn asynchronous query to synchronous by
adding C<< {async=>0} >> attribute - you don't have to rewrite code to
remove callback function. In this case your callback will be called
immediately after executing this synchronous query.

=over

=item connect(…)

L<DBD::mysql> support only single asynchronous query per MySQL connection.
To make it easier to overcome this limitation provided connect()
constructor work using DBI->connect_cached() under the hood, but it reuse
only inactive $dbh - i.e. one which you didn't use anymore. So, connect()
guarantee to not return $dbh which is already in use in your code.
For example, in FastCGI or Mojolicious app you can safely use connect() to
get own $dbh per each incoming connection; after you send response and
close this connection that $dbh should automatically go out of scope and
become inactive (you can force this by C<$dbh=undef;>); after that this
$dbh may be returned by connect() when handling next incoming request.
As result you should automatically get a pool of connected $dbh which size
should match peak amount of simultaneously handled CGI requests.
You can flush that $dbh cache as documented by L<DBI> at any time.

NOTE: To implement this caching behavior this module catch DESTROY() for
$dbh and instead of destroying it (and calling $dbh->disconnect()) make it
available for next connect() call in cache. So, if you need to call
$dbh->disconnect() - do it manually and don't expect it to happens
automatically on $dbh DESTROY(), like it work in DBI.

Also, usual limitations for cached connections apply as documented by
L<DBI> (read: don't change $dbh configuration).

=item $dbh->do(…, sub { my ($rv, $dbh) = @_; … });

=item $sth->execute(…, sub { my ($rv, $sth) = @_; … });

=item $dbh->selectall_arrayref(…, sub { my ($ary_ref) = @_; … });

=item $dbh->selectall_hashref(…, sub { my ($hash_ref) = @_; … });

=item $dbh->selectcol_arrayref(…, sub { my ($ary_ref) = @_; … });

=item $dbh->selectrow_array(…, sub { my (@row_ary) = @_; … });

=item $dbh->selectrow_arrayref(…, sub { my ($ary_ref) = @_; … });

=item $dbh->selectrow_hashref(…, sub { my ($hash_ref) = @_; … });

=back


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

These DBI methods not supported yet (i.e. they work as usually - in
blocking mode), mostly because they internally run several queries and
should be completely rewritten to support non-blocking mode.

NOTE: You have to provide C<< {async=>0} >> attribute to prepare() before
using execute_array() or execute_for_fetch().

    $sth->execute_array(…)
    $sth->execute_for_fetch(…)
    $dbh->table_info(…)
    $dbh->column_info(…)
    $dbh->primary_key_info(…)
    $dbh->foreign_key_info(…)
    $dbh->statistics_info(…)
    $dbh->primary_key(…)
    $dbh->tables(…)


=head1 SUPPORT

Please report any bugs or feature requests through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=AnyEvent-DBI-MySQL>.
I will be notified, and then you'll automatically be notified of progress
on your bug as I make changes.

You can also look for information at:

=over

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=AnyEvent-DBI-MySQL>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/AnyEvent-DBI-MySQL>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/AnyEvent-DBI-MySQL>

=item * Search CPAN

L<http://search.cpan.org/dist/AnyEvent-DBI-MySQL/>

=back


=head1 SEE ALSO

L<AnyEvent>, L<DBI>, L<AnyEvent::DBI>


=head1 AUTHOR

Alex Efros  C<< <powerman@cpan.org> >>


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Alex Efros <powerman@cpan.org>.

This program is distributed under the MIT (X11) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

