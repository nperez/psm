use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'POE::Session::Moose',
    license             => 'gpl',
    dist_author         => 'Nicholas <nperez@cpan.org>',
    dist_version_from   => 'lib/POE/Session/Moose.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'POE-Session-Moose-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
