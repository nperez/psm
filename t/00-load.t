#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'POEx::Role::SessionInstantiation' );
}

diag( "Testing POEx::Role::SessionInstantiation $POEx::Role::SessionInstantiation::VERSION, Perl $], $^X" );
