use Test::More;
use POE;
use MooseX::Declare;

use lib 't/lib';

class My::Session
{
    use Test::More;
    use aliased 'POEx::Role::Event';
    use MyTrait;
    use POEx::Role::SessionInstantiation(traits => [['MyTrait' => { attr => 'foo' }], ['MyTrait' => { attr => 'bar' }]]);
    with 'POEx::Role::SessionInstantiation';

    method _stop is Event
    {
        is($self->foo, 1, 'Trait worked appropriately: foo');
        is($self->bar, 1, 'Trait worked appropriately: bar');
        pass('Stop called');
    }
    
    after _start is Event
    {
        pass('Start called');
    }
}

class My::Session2
{
    use Test::More;
    use aliased 'POEx::Role::Event';
    use MyTrait;
    use POEx::Role::SessionInstantiation(traits => [ 'MyTrait' => { attr => 'baz' } ]);
    with 'POEx::Role::SessionInstantiation';

    method _stop is Event
    {
        is($self->baz, 1, 'Trait worked appropriately: baz');
        pass('Stop called');
    }
    
    after _start is Event
    {
        pass('Start called');
    }
}

class My::Session3
{
    use Test::More;
    use aliased 'POEx::Role::Event';
    use MyTrait;
    use POEx::Role::SessionInstantiation(traits => [ ['MyTrait'], [ 'MyTrait' => { attr => 'zarg' } ] ]);
    with 'POEx::Role::SessionInstantiation';

    method _stop is Event
    {
        is($self->blarg, 1, 'Trait worked appropriately: blarg');
        is($self->zarg, 1, 'Trait worked appropriately: zarg');
        pass('Stop called');
    }
    
    after _start is Event
    {
        pass('Start called');
    }
}
My::Session->new( options => { 'trace' => 1 } );
My::Session2->new( options => { 'trace' => 1 } );
My::Session3->new( options => { 'trace' => 1 } );

POE::Kernel->run();
done_testing();
1;
