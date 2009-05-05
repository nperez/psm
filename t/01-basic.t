use Test::More('tests', 11);
use POE;
use MooseX::Declare;

my $test = 0;

class My::Session with POEx::Role::SessionInstantiation
{
    use 5.010;

    sub _start
    {
        my $self = shift(@_);
        my $alias = shift(@_);
        Test::More::pass('Start called');
        $self->alias($alias);
        $self->yield('foo');
    }

    sub _stop
    {
        Test::More::pass('Stop called');
    }

    sub foo
    {
        my $self = shift(@_);
        Test::More::pass('foo called');
        if($test == 0)
        {
            $self->poe()->kernel()->state
            (
                'bar',
                sub
                {
                    my $self = shift(@_);
                    Test::More::pass('bar called');
                    
                    # create a named class instantiated object and post to it
                    my $class1 = Moose::Meta::Class->create('My::SubSession', roles => ['POEx::Role::SessionInstantiation'], superclasses => ['Moose::Object']);
                    $class1->add_method('blat', sub { Test::More::pass('blat called'); shift->poe->kernel->detach_myself(); });
                    $class1->name->new({ options => { 'trace' => 1 }, alias => 'blat_alias' });
                    $self->post('blat_alias', 'blat');
                    
                    # now do the same but anonymous
                    my $class2 = Moose::Meta::Class->create_anon_class(roles => ['POEx::Role::SessionInstantiation'], superclasses => ['Moose::Object']);
                    $class2->add_method('flarg', sub { Test::More::pass('flarg called'); shift->poe->kernel->detach_myself(); });
                    my $obj = $class2->name->new({ options => { 'trace' => 1 }, alias => 'flarg_anon_alias' });
                    $self->post('flarg_anon_alias', 'flarg');
                }
            );
            $test++;
        }
        elsif($test == 1)
        {   
            # remove foo from test1
            $self->poe()->kernel()->state
            (
                'foo',
                undef
            );
            
            # post an event to non-existent foo
            $self->yield('foo');
            $test++;
        }
        
        # only test0 should have this event
        $self->yield('bar');
    }

    sub _default
    {
        my ($self) = (shift);
        given($self->poe->state)
        {
            when('foo') { Test::More::pass('default redirect foo'); }
            when('bar') { Test::More::pass('default redirect bar'); }
        }
    }

    1;
}

my $sess = My::Session->new({ options => { 'trace' => 1 }, args => [ 'test0' ] });
my $sess2 = My::Session->new({ options => { 'trace' => 1 }, args => [ 'test1' ] });

POE::Kernel->run();

1;
