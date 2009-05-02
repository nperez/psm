use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'POEx::Role::SessionInstantiation',
    license             => 'gpl',
    dist_author         => 'Nicholas R. Perez <nperez@cpan.org>',
    dist_version_from   => 'lib/POEx/Role/SessionInstantiation.pm',
    dist_abstract       => 'A POE::Session implementation as a Moose::Role',
    create_readme       => 1,
    meta => 
    {
        resources =>
        {
            repository => 'git://nickandperla.net/pxrsi.git/'
        }
    },
    build_requires => 
    {
        'Test::More'        => 0,
        'POE'               => 1.004,
        'MooseX::Declare'   => 0.10,
    },
    add_to_cleanup      => [ 'POE-Session-Moose-*' ],
);

$builder->create_build_script();
