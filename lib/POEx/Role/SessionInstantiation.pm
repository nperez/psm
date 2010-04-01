package POEx::Role::SessionInstantiation;
use MooseX::Declare;

#ABSTRACT: A Moose Role for turning objects into POE Sessions

=head1 SYOPSIS

    package My::Class;
    use 5.010;
    use MooseX::Declare;

    class My::Class 
    {
        # using the role instantly makes it a POE::Session upon instantiation
        with 'POEx::Role::SessionInstantiation';
        # alias the decorator
        use aliased 'POEx::Role::Event';

        # decorated methods are all exposed as events to POE
        method foo (@args) is Event
        {
            # This event is not only added through POE but also added as a 
            # method to each instance that happens to have 'foo' fired

            # Access to POE information is done through the 'poe' accessor
            $self->poe->kernel->state
            (
                'added_event',
                sub
                {
                    say 'added_event has fired'
                }
            );

            # Some sugar to access the kernel's yield method
            # This will push the 'bar' method into POE's event queue
            $self->yield('bar');
        }

        method bar (@args)
        {
            # $self is also safe to pass as a session reference
            # Or you can pass along $self->ID()
            $self->post($self, 'baz')
        }

        method baz (@args)
        {
            # call also works too
            $self->call($self, 'added_event';
        }
    }

    # Constructing the session takes all the normal options
    my $session = My::Class->new({ options => { trace => 1 } });

    # Still need to call ->run();
    POE::Kernel->run();

=cut

role POEx::Role::SessionInstantiation with MooseX::CompileTime::Traits
{
    with 'POEx::Role::SessionInstantiation::Meta::Session::Magic';
    with 'POEx::Role::SessionInstantiation::Meta::Session::Implementation';
    with 'POEx::Role::SessionInstantiation::Meta::Session::Events';
    with 'POEx::Role::SessionInstantiation::Meta::Session::Sugar';
}
1;

__END__

=head1 DESCRIPTION

POEx::Role::SessionInstantiation provides a nearly seamless integration for 
non-POE objects into a POE environment. It does this by handling the POE stuff
behind the scenes including allowing per instances method changes, session 
registration to the Kernel, and providing some defaults like setting an alias
if supplied via the attribute or constructor argument, or defining a _default
that warns if your object receives an event that it does not have.

This role exposes your class' methods as POE events.

=head1 NOTES

Like all dangerous substances, this Role needs a big fat warning. It should be
noted thoroughly that this Role performs some pretty heinous magic to 
accomplish a polished and consistent transformation of your class into a 
Session. 

=over 4

=item PER INSTANCE METHOD CHANGES

This Role enables your /objects/ to have method changes. You read that right. 
POE allows Sessions to have runtime event handler modification. It is sort of 
required to support wheels and whatever. Anyhow, to support that functionality
class level changes are executed via Moose::Meta::Class to add/change/remove 
methods as events are added, changed, and removed via POE. But how is that
possible, you ask, to make class level changes without affecting all of the 
other instances? An anonymous clone of the composed class is created and the 
object is reblessed into that new clone that has changes for each change to the
events that occurs. This segregates changes so that they only affect the 
individual object involved. 

This functionality should likely be broken out into its own evil module, but
that is a job for another day.

=item BREAKING POE ENCAPSULATION

POE internally tracks Sessions by their stringified reference. So how do make
changes to references, such as reblessing them into different classes, and not 
break POE? You do some scary crap. Stringification is overloaded (via overload
pragma) to return the original string from the instance before changes are made
to it and it is reblessed. The original string is stored in the orig attribute.
POE also does reference comparisons as well to check if the current session is
the same as the one it just got and so != and == are also overloaded to do 
string comparisons of references. But what about the reference that is already
stored by POE? The reference is overwritten in one spot (where POE stores its
Sessions) and is done every time an event change takes place.

=item OVERLOAD PRAGMA IN A ROLE? WTF?

Moose does the right thing, mostly, when it comes to the overload pragma in a 
Role. The methods defined are composed appropriate, but the magic doesn't make
it through the composition. So the magic must be enabled manually. This 
includes messing with the symbol table of the composed class. This happens 
inside the after 'BUILD' advice, and also during event handler changes from POE
(the anonymous classes need to have the magic enabled each time). So what is
the moral to this? If you need to overload "", !=, or == in your composed class
things will likely break. You have been warned.

=back

So please heed the warnings and don't blame me if this summons the terrasque 
into your datacenter and you left your +5 gear at home.

=head1 FURTHER NOTES

=head2 CUSTOMIZING VIA TRAITS

POEx::Role::SessionInstantiation now allows for Trait declarations upon import.
This is similar to how Moose itself allows for modification of its own Meta
things through arguments passed to use (ie. use Moose -traits => qw /Foo/), but
allows for parameterized roles. Below are some examples of using traits to
modify POEx::Role::SessionInstantiation's default behavior.

First let's declare a role that frobinates something at start:

    use MooseX::Declare;

    role FrobAtStart
    {
        with 'POEx::Role::SessionInstantiation::Meta::Session::Events';
        
        has frobinator =>
        (
            is => 'ro', 
            isa => 'Object', 
            required => 1,
            handles =>
            {
                'frob' => 'frob'
            }
        );

        after _start is POEx::Role::Event
        {
            $self->frob();
        }
    }

And how about a logger role that logs unknown delivered events that wants the
logging method/event to be a named parameter

    role SomeLogger(Str :$foo)
    {
        with 'POEx::Role::SessionInstantiation::Meta::Session::Events';

        has logger =>
        (
            is => 'ro', 
            isa => 'Object', 
            required => 1 
        );

        method $foo(Str $event) is POEx::Role::Event
        {
            $self->logger->log("Unknown event: $event") 
        }

        after _default is POEx::Role::Event
        {
            $self->$foo($self->poe->state);
        }
    }

Now let's use them

    class My::Session
    {
        # need to make sure these are loaded 
        use FrobinateAtStart;
        use SomeLogger;
        
        # and now the magic
        use POEx::Role::SessionInstantiation 
            traits => [ 'FrobAtStart', SomeLogger => { foo => 'log' } ];
        
        # compose it now that it has traits applied
        with 'POEx::Role::SessionInstantiation';
        ...
    }

For more information on how this mechanism works, please see
MooseX::CompileTime::Traits

=head2 WRITING YOUR OWN TRAITS

To make it easy to advise just little parts of POEx::Role::SessionInstantiation
it is broken down into a few different roles that you can 'with' like in the 
examples above.

=over 4

=item POEx::Role::SessionInstantiation::Meta::Session::Magic

This is where the voodoo happens to turn your objects into sessions.

=item POEx::Role::SessionInstantiation::Meta::Session::Events

Here are the default events such as _start, _stop, _default, etc.

=item POEx::Role::SessionInstantiation::Meta::Session::Sugar

This role holds the delegated methods from POE::Kernel (post, yield, call)

=item POEx::Role::SessionInstantiation::Meta::Session::Implementation

And this is the implementation piece that implements the POE::Session
interface that lets POE interact with our sessions

=back

Please see their POD for more details on the inner workings of this module.

