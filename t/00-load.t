#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'POE::Session::Moose' );
}

diag( "Testing POE::Session::Moose $POE::Session::Moose::VERSION, Perl $], $^X" );
