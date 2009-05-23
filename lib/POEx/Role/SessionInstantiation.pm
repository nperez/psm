package POEx::Role::SessionInstantiation;
use 5.010;
use MooseX::Declare;

#ABSTRACT: A Moose Role for turning objects into POE Sessions

=head1 SYOPSIS

    package My::Class;
    use 5.010;
    use MooseX::Declare;

    # using the role instantly makes it a POE::Session upon instantiation
    class My::Class with POEx::Role::SessionInstantiation
    {
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

role POEx::Role::SessionInstantiation
{
    use MooseX::Types::Moose('Str', 'Int', 'Any', 'HashRef', 'Object', 'ArrayRef', 'Maybe');
    use POEx::Types(':all');
    use Moose::Util::TypeConstraints;
    use signatures;
    use POE;

    use aliased 'POEx::Role::Event', 'Event';

    use overload '""' => sub
    { 
        my $s = shift;
        return $s->orig if $s->orig; 
        return $s; 
    };

    use overload '!=' => sub
    {
        return "$_[0]" ne "$_[1]";
    };

    use overload '==' => sub
    {
        return "$_[0]" eq "$_[1]";
    };

    has orig => ( is => 'rw', isa => Str);

=attr heap is: rw, isa: Any, default: {}, lazy: yes  

A traditional POE::Session provides a set aside storage space for the session
context and that space is provided via argument to event handlers. With this 
Role, your object gains its own heap storage via this attribute.
=cut

    has heap =>
    (
        is => 'rw',
        isa => Any,
        default => sub { {} },
        lazy => 1,
    );

=attr options is: rw, isa: HashRef, default: {}, lazy: yes

In following the POE::Session API, sessions can take options that do various
things related to tracing and debugging. By default, tracing => 1, will turn on
tracing of POE event firing to your object. debug => 1, currently does nothing 
but more object level tracing maybe enabled in future versions.

=cut

    has options =>
    (
        is => 'rw',
        isa => HashRef,
        default => sub { {} },
        lazy => 1,
    );

=attr poe is: ro, isa: Object

The poe attribute provides runtime context for your object methods. It contains
an anonymous object with it's own attributes and methods. Runtime context is 
built for each individual event handler invocation and then torn down to avoid
context crosstalk. It is important to only access this attribute from within a 
POE invoked event handler. 

=head3 POE ATTRIBUTES

=over 4

=item sender is: rw, isa: POE::Kernel | POE::Session | ->does(SessionInstant.)

The sender of the current event can be access from here. Semantically the same
as $_[+SENDER].

=item state is: rw, isa: Str

The state fired. This should match the current method name (unless of course
within the _default event handler, then it will be the event name that was 
invoked but did not exist in your object instance.

=item [qw/file line from/] is: rw, isa: Maybe[Str]

These attributes provide tracing information from within POE. From is actually
not used in POE::Session as far as I can tell, but it is available just in 
case.

=item kernel is: rw, isa: POE::Kernel

This is actually the POE::Kernel singleton provided as a little sugar instead
of requiring use of $poe_kernel, etc. To make sure you are currently within a 
POE context, check this attribute for definedness.

=back

=head3 POE PRIVATE METHODS

=over 4

=item clear()

This will clear the all of the current context information.

=item restore($poe)

This will take another anonymous poe object and restore state.

=item clone()

This will clone the current anonymous poe object and return it.

=back

=cut

    has poe =>
    (
        is => 'ro',
        isa => Object,
        lazy_build => 1,
    );

    sub _build_poe
    {
        state $poe_class = class 
        {
            use POEx::Types(':all');
            use MooseX::Types::Moose('Maybe', 'Str');

            has sender  => ( is => 'rw', isa => Kernel|Session|DoesSessionInstantiation, clearer => 'clear_sender'  );
            has state   => ( is => 'rw', isa => Str, clearer => 'clear_state' );
            has file    => ( is => 'rw', isa => Maybe[Str], clearer => 'clear_file' );
            has line    => ( is => 'rw', isa => Maybe[Str], clearer => 'clear_line' );
            has from    => ( is => 'rw', isa => Maybe[Str], clearer => 'clear_from' );
            has kernel  => ( is => 'rw', isa => Kernel, clearer => 'clear_kernel' );

            method clear
            {
                $self->clear_sender;
                $self->clear_state;
                $self->clear_file;
                $self->clear_line;
                $self->clear_from;
                $self->clear_kernel;
            }

            method restore (Object $poe)
            {
                $self->sender($poe->sender);
                $self->state($poe->state);
                $self->file($poe->file);
                $self->line($poe->line);
                $self->from($poe->from);
                $self->kernel($poe->kernel);
            }

            method clone
            {
                return $self->meta->clone_object($self);
            }
        };

        return $poe_class->name->new();
    }

=attr args is: rw, isa: ArrayRef, default: [], lazy: yes

POE::Session's constructor provides a mechanism for passing arguments that will
end up as arguments to the _start event handler. This is the exact same thing.

=cut

    has args =>
    (
        is => 'rw',
        isa => ArrayRef,
        default => sub { [] },
        lazy => 1
    );

=attr alias is: rw, isa: Str, clearer: clear_alias, trigger: registers alias

This attribute controls your object's alias to POE. POE allows for more than
one alias to be assigned to any given session, but this attribute only assumes
a single alias will not attempt to keep track of all the aliases. Last alias
set will be what is returned. Calling the clearer will remove the last alias
set from POE and unset it. You must be inside a valid POE context for the 
trigger to actually fire (ie, inside a event handler that has been invoked from
POE). While this can be set at construction time, it won't be until _start that
it will actually register with POE. If you override _start, don't forget to set
this attribute again ( $self->alias($self->alias); ) or else your alias will 
never get registered with POE.

=cut

    has alias =>
    (
        is => 'rw',
        isa => Str,
        trigger => sub ($self, $val)
        { 
            # we need to check to make sure we are currently in a POE context
            return if not defined($self->poe->kernel);
            $POE::Kernel::poe_kernel->alias_set($val); 
        },
        clearer => '_clear_alias',
    );

=attr ID is: ro, isa: Int

This attribute will return what your POE assigned Session ID is. Must only be
accessed after your object has been fully built (ie. after any BUILD methods).
This ID can be used, in addition to a reference to yourself, and your defined
alias, by other Sessions for addressing events sent through POE to your object.

=cut

    has ID =>
    (
        is => 'ro',
        isa => Int,
        default => sub ($self) { $POE::Kernel::poe_kernel->ID_session_to_id($self) },
        lazy => 1,
    );

    # this just stores the anonymous clone class we create for our instance
    has _self_meta =>
    (
        is => 'rw',
        isa => 'Class::MOP::Class'
    );
=method [qw/post yield call/]

These are provided as sugar for the respective POE::Kernel methods.

=cut
    # add some sugar for posting, yielding, and calling events
    method post(SessionAlias|SessionID|Session|DoesSessionInstantiation $session, Str $event_name, @args) 
    {
        confess('No POE context') if not defined($self->poe->kernel);
        return $self->poe->kernel->post($session, $event_name, @args);
    }

    method yield(Str $event_name, @args)
    {
        confess('No POE context') if not defined($self->poe->kernel);
        return $self->poe->kernel->yield($event_name, @args);
    }

    method call(SessionAlias|SessionID|Session|DoesSessionInstantiation $session, Str $event_name, @args) 
    {
        confess('No POE context') if not defined($self->poe->kernel);
        return $self->poe->kernel->call($session, $event_name, @args);
    }

=method _start(@args)

Provides a default _start event handler that will be invoked from POE once the
Session is registered with POE. The default method only takes the alias 
attribute and sets it again to activate the trigger. If this is overridden, 
don't forget to set the alias again so the trigger can execute.

=cut

    # some defaults for _start, _stop and _default
    method _start(@args) is Event
    {
        if($self->alias)
        {
            # inside a poe context now, so fire the trigger
            $self->alias($self->alias);
        }
        1;
    }

=method _stop()

Provides a default _stop event handler that will be invoked from POE once the 
Session's refcount from within POE has reached zero (no pending events, no
event sources, etc). The default method merely clears out the alias.

=cut
    method _stop() is Event
    { 
        $self->clear_alias();
        1;
    }

=method _default(ArrayRef $args)

Provides a _default event handler to catch any POE event invocations that your
instance does not actually have. Will 'warn' about the nonexistent state. A big
difference from POE::Session is that the state and arguments are not rebundled 
upon invocation of this event handler. Instead the attempted state will be
available in the poe attribute, but the arguments are still bundled into a 
single ArrayRef

=cut

    method _default(ArrayRef $args?) is Event
    {
        my $string = $self->alias // $self->ID;
        my $state = $self->poe->state;
        warn "Nonexistent '$state' event delivered to $string";
    }

=method _child(Str $event, Session $child, Any $ret?)

Provides a _child event handler that will be invoked when child sesssions are
created, destroyed or reassigned to or from another parent. See POE::Kernel for
more details on this event and its semantics

=cut

    method _child(Str $event, Session|DoesSessionInstantiation $child, Any $ret?) is Event
    {
        1;
    }

=method _parent(Session $previous_parent, Session $new_parent)

Provides a _parent event handler. This is used to notify children session when
their parent has changes. See POE::Kernel for more details on this event.

=cut

    method _parent(Session|DoesSessionInstantiation $previous_parent, Session|DoesSessionInstantiation $new_parent) is Event
    {
        1;
    }

    sub BUILD { 1; }

=method after BUILD

All of the magic for turning the constructed object into a Session happens in 
this method. If a BUILD is not provided, a stub exists to make sure this advice
is executed.

=cut
    after BUILD(@args)
    {
        #enable overload in the composed class (ripped from overload.pm)
        {
            no strict 'refs';
            no warnings 'redefine';
            ${$self->meta->name . "::OVERLOAD"}{dummy}++;
            *{$self->meta->name . "::()"} = sub {};
        }

        # we need a no-op bless here to activate the magic for overload
        bless ({}, $self->meta->name);
        
        #this registers us with the POE::Kernel
        $POE::Kernel::poe_kernel->session_alloc($self, @{$self->args()})
            if not $self->orig;
    };

    method clear_alias
    {
        $POE::Kernel::poe_kernel->alias_remove($self->alias());
        $self->_clear_alias();
    }

    method _invoke_state(Kernel|Session|DoesSessionInstantiation $sender, Str $state, ArrayRef $etc, Str $file?, Int $line?, Str $from?)
    {
        my $method = $self->meta()->find_method_by_name($state);

        if(defined($method))
        {
            if($method->isa('Class::MOP::Method::Wrapped'))
            {
                my $orig = $method->get_original_method;
                if(!$orig->meta->isa('Moose::Meta::Class') || !$orig->meta->does_role('POEx::Role::Event'))
                {
                    POE::Kernel::_warn($self->ID, " -> $state [WRAPPED], called from $file at $line, exists, but is not marked as an available event");
                    return;
                }

            }
            elsif(!$method->meta->isa('Moose::Meta::Class') || !$method->meta->does_role('POEx::Role::Event'))
            {
                warn $method->meta->dump(2);
                POE::Kernel::_warn($self->ID, " -> $state, called from $file at $line, exists, but is not marked as an available event");
                return;
            }

            my $poe = $self->poe();

            my $saved;
            if(defined($poe->kernel))
            {
                $saved = $poe->clone();
            }

            $poe->sender($sender);
            $poe->state($state);
            $poe->file($file);
            $poe->line($line);
            $poe->from($from);
            $poe->kernel($POE::Kernel::poe_kernel);

            POE::Kernel::_warn($self->ID(), " -> $state (from $file at $line)\n" )
                if $self->options->{trace};

            my $return = $method->execute($self, @$etc);
            $poe->clear();
            $poe->restore($saved) if defined $saved;
            return $return;

        }
        else
        {
            my $default = $self->meta()->find_method_by_name('_default');

            if(defined($default))
            {
                if($default->meta->isa('Class::MOP::Method::Wrapped'))
                {
                    my $orig = $default->get_original_default;
                    if(!$orig->meta->isa('Moose::Meta::Class') || !$orig->meta->does_role('POEx::Role::Event'))
                    {
                        POE::Kernel::_warn($self->ID, " -> $state [WRAPPED], called from $file at $line, exists, but is not marked as an available event");
                        return;
                    }
                }
                elsif(!$default->meta->isa('Moose::Meta::Class') || !$default->meta->does_role('POEx::Role::Event'))
                {
                    POE::Kernel::_warn($self->ID, " -> $state, called from $file at $line, exists, but is not marked as an available event");
                    return;
                }
                my $poe = $self->poe();

                my $saved;
                if(defined($poe->kernel))
                {
                    $saved = $poe->clone();
                }

                $poe->sender($sender);
                $poe->state($state);
                $poe->file($file);
                $poe->line($line);
                $poe->from($from);
                $poe->kernel($POE::Kernel::poe_kernel);
                
                my $return = $default->execute($self, $etc);
                $poe->clear();
                $poe->restore($saved) if defined $saved;
                return $return;
            }
            else
            {
                my $loggable_self = $self->alias // $self->ID;
                POE::Kernel::_warn
                (
                    "a '$state' event was sent from $file at $line to $loggable_self ",
                    "but $loggable_self has neither a handler for it ",
                    "nor one for _default\n"
                );
            }
        }
    }

    method _register_state (Str $method_name, CodeRef|MooseX::Method::Signatures::Meta::Method $coderef?, Str $ignore?)
    {
        
        # per instance changes
        $self = $self->_clone_self();

        if(!defined($coderef))
        {
            # we mean to remove this method
            $self->meta()->remove_method($method_name);
        }
        else
        {
            # horrible hack to make sure wheel states get called how they want to be called
            if($method_name =~ /POE::Wheel/)
            {
                $coderef = $self->_wheel_wrap_method($coderef);
            }
            # otherwise, it is either replace it or add it
            my $method = $self->meta()->find_method_by_name($method_name);

            if(defined($method))
            {
                $self->meta()->remove_method($method_name);
            }
            
            my ($new_method, $superclass);

            if(blessed($coderef) && $coderef->isa('MooseX::Method::Signatures::Meta::Method'))
            {
                $new_method = $coderef;
                $superclass = 'MooseX::Method::Signatures::Meta::Method';
                
                if($new_method->isa('Moose::Meta::Class') && $new_method->does_role(Event))
                {
                    $self->meta->add_method($method_name, $new_method);
                    return;
                }

            }
            else
            {
                $superclass = 'Moose::Meta::Method';
                $new_method = Moose::Meta::Method->wrap
                (
                    $coderef, 
                    (
                        name => $method_name,
                        package_name => ref($self)
                    )
                );
            }
            
            my $anon = Moose::Meta::Class->create_anon_class
            (
                superclasses => [ $superclass ],
                roles => [ Event ],
                cache => 1,
            );

            bless($new_method, $anon->name);
 
            $self->meta->add_method($method_name, $new_method);

        }
    }

    # we need this to insure that wheel states get called how they think they should be called
    # Note: this is a horrible hack.
    method _wheel_wrap_method (CodeRef|MooseX::Method::Signatures::Meta::Method $ref)
    {
        sub ($obj)
        {
            my $poe = $obj->poe;
            my @args;
            (
                $args[OBJECT] , 
                $args[SESSION], 
                $args[KERNEL], 
                $args[HEAP], 
                $args[STATE],
                $args[SENDER], 
                $args[6], 
                $args[CALLER_FILE], 
                $args[CALLER_LINE], 
                $args[CALLER_STATE]
            ) = ($obj, $obj, $poe->kernel, $obj->heap, $poe->state, $poe->sender, undef, $poe->file, $poe->line, $poe->from);

            return $ref->(@args, @_);
        }
    }

    method _clone_self
    {
        # we only need to clone once
        if($self->orig)
        {
            return $self;
        }

        # we need to hold on to the original stringification
        my $orig = "$self";
        $self->orig($orig);

        my $meta = $self->meta();
        my $anon = Moose::Meta::Class->create_anon_class
        (   
            superclasses => [ $meta->superclasses() ],
            methods => { map { $_->name,  $_  } $meta->get_all_methods },
            attributes => [ $meta->get_all_attributes() ],
            roles => [ map { $_->name } @{$meta->roles} ],
        );

        #enable overload in the anonymous class (ripped from overload.pm)
        {
            no strict 'refs';
            no warnings 'redefine';
            ${$anon->name . "::OVERLOAD"}{dummy}++;
            *{$anon->name . "::()"} = sub {};
        }

        # this bless not only reblesses into the anonymous class, but also activates overload
        bless($self, $anon->name);

        # and to keep our anonymous class from going out of scope, stash a reference into ourselves
        $self->_self_meta($anon);

        # And here is where we break POE encapsulation
        $POE::Kernel::poe_kernel->[POE::Kernel::KR_SESSIONS]->{$orig}->[POE::Kernel::SS_SESSION] = $self;

        return $self;
    }
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

