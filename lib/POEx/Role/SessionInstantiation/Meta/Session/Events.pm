package POEx::Role::SessionInstantiation::Meta::Session::Events;

#ABSTRACT: Provides default events such as _start, _stop, etc

use MooseX::Declare;

role POEx::Role::SessionInstantiation::Meta::Session::Events
{
    use POEx::Types(':all');
    use aliased 'POEx::Role::Event';

=method_private _start

    is Event

Provides a default _start event handler that will be invoked from POE once the
Session is registered with POE. The default method only takes the alias 
attribute and sets it again to activate the trigger. If this is overridden, 
don't forget to set the alias again so the trigger can execute.

=cut

    method _start is Event
    {
        if($self->alias)
        {
            # inside a poe context now, so fire the trigger
            $self->alias($self->alias);
        }
        1;
    }

=method_private _stop()

    is Event

Provides a default _stop event handler that will be invoked from POE once the 
Session's refcount from within POE has reached zero (no pending events, no
event sources, etc). The default method merely clears out the alias.

=cut

    method _stop() is Event
    { 
        $self->clear_alias();
        1;
    }

=method_private _default

    (Maybe[ArrayRef] $args) is Event

Provides a _default event handler to catch any POE event invocations that your
instance does not actually have. Will 'warn' about the nonexistent state. A big
difference from POE::Session is that the state and arguments are not rebundled 
upon invocation of this event handler. Instead the attempted state will be
available in the poe attribute, but the arguments are still bundled into a 
single ArrayRef

=cut

    method _default(Maybe[ArrayRef] $args) is Event
    {
        my $string = defined($self->alias) ? $self->alias : $self->ID;
        my $state = $self->poe->state;
        warn "Nonexistent '$state' event delivered to $string";
    }

=method_private _child

    (Str $event, Session|DoesSessionInstantiation $child, Any $ret) is Event

Provides a _child event handler that will be invoked when child sesssions are
created, destroyed or reassigned to or from another parent. See POE::Kernel for
more details on this event and its semantics

=cut

    method _child(Str $event, Session|DoesSessionInstantiation $child, Any $ret) is Event
    {
        1;
    }

=method_private _parent

    Session|DoesSessionInstantiation|Kernel $previous_parent, Session|DoesSessionInstantiation|Kernel $new_parent) is Event

Provides a _parent event handler. This is used to notify children session when
their parent has changes. See POE::Kernel for more details on this event.

=cut

    method _parent(Session|DoesSessionInstantiation|Kernel $previous_parent, Session|DoesSessionInstantiation|Kernel $new_parent) is Event
    {
        1;
    }
}

1;

__END__
