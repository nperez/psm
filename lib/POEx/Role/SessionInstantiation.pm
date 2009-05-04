package POEx::Role::SessionInstantiation;
use 5.010;
use Moose::Role;
use MooseX::Declare;
use Moose::Util::TypeConstraints;
use POE;

our $VERSION = '0.01';

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

has orig => ( is => 'rw', isa =>'Str');

subtype Kernel 
    => as 'POE::Kernel';

subtype Session
    => as 'POE::Session';

subtype CanDoSession
    => as 'Object',
    => where { $_->does(__PACKAGE__) };

has heap =>
(
    is => 'rw',
    isa => 'Any',
    default => sub { {} },
    lazy => 1,
);

has options =>
(
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    lazy => 1,
);

has poe =>
(
    is => 'ro',
    isa => 'Object',
    default => sub
    {
        my $class = class 
        {
            has sender  => ( is => 'rw', isa => 'Kernel | Session | CanDoSession', clearer => 'clear_sender'  );
            has state   => ( is => 'rw', isa => 'Str', clearer => 'clear_state' );
            has file    => ( is => 'rw', isa => 'Maybe[Str]', clearer => 'clear_file' );
            has line    => ( is => 'rw', isa => 'Maybe[Str]', clearer => 'clear_line' );
            has from    => ( is => 'rw', isa => 'Maybe[Str]', clearer => 'clear_from' );
            has kernel  => ( is => 'rw', isa => 'Kernel', clearer => 'clear_kernel' );

            sub clear
            {
                my $self = shift;
                $self->clear_sender;
                $self->clear_state;
                $self->clear_file;
                $self->clear_line;
                $self->clear_from;
                $self->clear_kernel;
            }

            sub restore
            {
                my $self = shift;
                my $poe = shift;
                $self->sender($poe->sender);
                $self->state($poe->state);
                $self->file($poe->file);
                $self->line($poe->line);
                $self->from($poe->from);
                $self->kernel($poe->kernel);
            }

            sub clone
            {
                my $self = shift;
                return $self->meta->clone_object($self);
            }
        };

        $class->new_object({});
    },
    lazy => 1
);

has args =>
(
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
    lazy => 1
);

has alias =>
(
    is => 'rw',
    isa => 'Str',
    trigger => sub 
    { 
        my ($self, $val) = (shift, shift);
        # we need to check to make sure we are currently in a POE context
        return if not defined($self->poe->kernel);
        $POE::Kernel::poe_kernel->alias_set($val); 
    },
    clearer => '_clear_alias',
);

has ID =>
(
    is => 'ro',
    isa => 'Int',
    default => sub { $POE::Kernel::poe_kernel->ID_session_to_id(shift) },
    lazy => 1,
);

# this just stores the anonymous clone class we create for our instance
has _self_meta =>
(
    is => 'rw',
    isa => 'Class::MOP::Class'
);

# add some sugar for posting, yielding, and calling events
sub post
{
    my ($self, $session, $event, @args) = @_;
    confess('No POE context') if not defined($self->poe->kernel);
    return $self->poe->kernel->post($session, $event, @args);
}

sub yield
{
    my ($self, $event, @args) = @_;
    confess('No POE context') if not defined($self->poe->kernel);
    return $self->poe->kernel->yield($event, @args);
}

sub call
{
    my ($self, $session, $event, @args) = @_;
    confess('No POE context') if not defined($self->poe->kernel);
    return $self->poe->kernel->call($session, $event, @args);
}

# some defaults for _start, _stop and _default
sub _start
{
    my $self = shift;
    if($self->alias)
    {
        # inside a poe context now, so fire the trigger
        $self->alias($self->alias);
    }
}

sub _stop 
{ 
    my $self = shift;
    $self->clear_alias();
}

sub _default 
{
    my $self = shift;
    my $string = $self->alias // $self;
    my $state = $self->poe->state;
    warn "Nonexistent '$state' event delivered to $string";
}

sub BUILD { 1; }

after 'BUILD' => sub
{
    my $self = shift(@_);

    #enable overload in the composed class (ripped from overload.pm)
    {
        no strict 'refs';
        no warnings 'redefine';
        ${$self->meta->name . "::OVERLOAD"}{dummy}++;
        *{$self->meta->name . "::()"} = sub {};
    }

    # we need a no-op bless here to activate the magic for overload
    bless ({}, $self->meta->name);

    if($self->options()->{'trace'})
    {
        $self = $self->_clone_self();
        my $meta = $self->meta();

        foreach my $name ($meta->get_all_method_names)
        {
            # This is a hack, there has to be a better moose idiom for this

            # Check to see if this method name is actually an attribute.
            # We don't want to trace attribute calls
            if ($meta->has_attribute($name))
            {
                next;
            }

            # Check for clearers and builders, this is another hack
            my $clearer = my $builder = $name;
            if($name =~ /_clear_/)
            {
                $clearer =~ s/_clear_//g;

                if($meta->has_attribute($clearer))
                {
                    next;
                }
            }

            if($name =~ /_build_/)
            {
                $builder =~ s/_build_//g;

                if($meta->has_attribute($builder))
                {
                    next;
                }
            }

            # Weed out any of the non-event methods from the Role
            if(__PACKAGE__->meta->has_method($name))
            {
                next;
            }

            # Make sure the Moose::Object stuff doesn't get traced either
            if('Moose::Object'->meta->has_method($name))
            {
                next;
            }

            # we have to use 'around' to gain access to the arguments
            $meta->add_around_method_modifier
            (
                $name, 
                sub
                {
                    my ($orig, $self, @etc) = @_;

                    my $poe = $self->poe();
                    my $state = $poe->state();
                    my $file = $poe->file();
                    my $line = $poe->line();

                    POE::Kernel::_warn($self->ID(), " -> $state (from $file at $line)\n" );

                    return $orig->($self, @etc);
                }
            );
        }
    }

    #this registers us with the POE::Kernel
    $POE::Kernel::poe_kernel->session_alloc($self, @{$self->args()});
};

sub clear_alias
{
    my $self = shift(@_);
    $POE::Kernel::poe_kernel->alias_remove($self->alias());
    $self->_clear_alias();
}

sub _invoke_state
{
    my $self    = shift(@_);
    my $sender  = shift(@_); 
    my $state   = shift(@_);
    my $etc     = shift(@_); 
    my $file    = shift(@_); 
    my $line    = shift(@_); 
    my $from    = shift(@_);

    my $method = $self->meta()->find_method_by_name($state);

    if(defined($method))
    {
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

            my $return = $default->execute($self, @$etc);
            $poe->clear();
            $poe->restore($saved) if defined $saved;
            return $return;
        }
        else
        {
            # this idiom was taken from POE::Session
            my $loggable_self = $POE::Kernel::poe_kernel->_data_alias_loggable($self);
            POE::Kernel::_warn
            (
                "a '$state' event was sent from $file at $line to $loggable_self ",
                "but $loggable_self has neither a handler for it ",
                "nor one for _default\n"
            );
        }
    }
}

sub _register_state
{
    # only support inline state usage
    my ($self, $method_name, $coderef) = @_;

    confess ('$method_name undefined!') unless $method_name;

    $self = $self->_clone_self();

    if(!defined($coderef))
    {
        # we mean to remove this method
        $self->meta()->remove_method($method_name);
    }
    else
    {
        # otherwise, it is either replace it or add it
        my $method = $self->meta()->find_method_by_name($method_name);

        if(defined($method))
        {
            $self->meta()->remove_method($method_name);
        }

        my $new_method = Class::MOP::Method->wrap
        (
            $coderef, 
            (
                name => $method_name,
                package_name => ref($self)
            )
        );

        $self->meta()->add_method($method_name, $new_method);

        # enable tracing on the added method if tracing is enabled
        if($self->options()->{'trace'})
        {
            my $meta = $self->meta();
            $meta->add_around_method_modifier
            (
                $method_name, 
                sub
                {
                    my ($orig, $self, @etc) = @_;

                    my $poe = $self->poe();
                    my $state = $poe->state();
                    my $file = $poe->file();
                    my $line = $poe->line();

                    POE::Kernel::_warn($self->ID(), " -> $state (from $file at $line)\n" );

                    return $orig->($self, @etc);
                }
            );
        }
    }
}

sub _clone_self
{
    my $self = shift;

    my $meta = $self->meta();
    my $anon = Moose::Meta::Class->create_anon_class
    (   
        superclasses => [ $meta->superclasses() ],
        methods => { map { $_->name,  $_->body  } $meta->get_all_methods },
        attributes => [ $meta->get_all_attributes() ],
        roles => [ map { $_->name } $meta->calculate_all_roles() ] ,
    );

    # we need to hold on to the original stringification
    my $orig = "$self";

    #enable overload in the anonymous class (ripped from overload.pm)
    {
        no strict 'refs';
        no warnings 'redefine';
        ${$anon->name . "::OVERLOAD"}{dummy}++;
        *{$anon->name . "::()"} = sub {};
    }

    # this bless not only reblesses into the anonymous class, but also activates overload
    bless($self, $anon->name);

    # we only want to store the original class stringification to fool POE
    if(!defined($self->orig))
    {
        $self->orig($orig);
    }

    # and to keep our anonymous class from going out of scope, stash a reference into ourselves
    $self->_self_meta($anon);

    # And here is where we break POE encapsulation
    $POE::Kernel::poe_kernel->[POE::Kernel::KR_SESSIONS]->{$orig}->[POE::Kernel::SS_SESSION] = $self;

    return $self;

}

no Moose::Role;

=pod

=head1 NAME

POEx::Role::SessionInstantiation - A Moose::Role for plain old Perl objects in 
a POE context

=head1 SYOPSIS

    package My::Class;
    use 5.010;
    use MooseX::Declare;

    # using the role instantly makes it a POE::Session upon instantiation
    class My::Class with POEx::Role::SessionInstantiation
    {
        # declared methods are all exposed as events to POE
        sub foo
        {
            my ($self, @args) = @_;

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

        sub bar
        {
            my ($self, @args) = @_;

            # $self is also safe to pass as a session reference
            # Or you can pass along $self->ID()
            $self->post($self, 'baz')
        }

        sub baz
        {
            my ($self, @args) = @_;

            # call also works too
            $self->call($self, 'added_event';
        }
    }

    1;

    # Constructing the session takes all the normal options
    my $session = My::Class->new({ options => { trace => 1 } });

    # Still need to call ->run();
    POE::Kernel->run();

=head1 DESCRIPTION

POEx::Role::SessionInstantiation provides a nearly seamless integration for 
non-POE objects into a POE environment. It does this by handling the POE stuff
behind the scenes including allowing per instances method changes, session 
registration to the Kernel, and providing some defaults like setting an alias
if supplied via the attribute or constructor argument, or defining a _default
that warns if your object receives an event that it does not have.

This role exposes your class' methods as POE events.

=head1 ATTRIBUTES

=over 4

=item heap is: rw, isa: Any, default: {}, lazy: yes  

A traditional POE::Session provides a set aside storage space for the session
context and that space is provided via argument to event handlers. With this 
Role, your object gains its own heap storage via this attribute.

=item options is: rw, isa: HashRef, default: {}, lazy: yes

In following the POE::Session API, sessions can take options that do various
things related to tracing and debugging. By default, tracing => 1, will turn on
tracing of POE event firing to your object. debug => 1, currently does nothing 
but more object level tracing maybe enabled in future versions.

=item args is: rw, isa: ArrayRef, default: [], lazy: yes

POE::Session's constructor provides a mechanism for passing arguments that will
end up as arguments to the _start event handler. This is the exact same thing.

=item alias is: rw, isa: Str, clearer: clear_alias, trigger: registers alias

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

=item ID is: ro, isa: Int

This attribute will return what your POE assigned Session ID is. Must only be
accessed after your object has been fully built (ie. after any BUILD methods).
This ID can be used, in addition to a reference to yourself, and your defined
alias, by other Sessions for addressing events sent through POE to your object.

=item poe is: ro, isa: Object

The poe attribute provides runtime context for your object methods. It contains
an anonymous object with it's own attributes and methods. Runtime context is 
built for each individual event handler invocation and then torn down to avoid
context crosstalk. It is important to only access this attribute from within a 
POE invoked event handler. 

POE ATTRIBUTES

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

POE PRIVATE METHODS

=over 4

=item clear()

This will clear the all of the current context information.

=item restore($poe)

This will take another anonymous poe object and restore state.

=item clone()

This will clone the current anonymous poe object and return it.

=back

=back

=head1 METHODS

=over 4

=item [qw/post yield call/]

These are provided as sugar for the respective POE::Kernel methods.

=item _start

Provides a default _start event handler that will be invoked from POE once the
Session is registered with POE. The default method only takes the alias 
attribute and sets it again to activate the trigger. If this is overridden, 
don't forget to set the alias again so the trigger can execute.

=item _stop

Provides a default _stop event handler that will be invoked from POE once the 
Session's refcount from within POE has reached zero (no pending events, no
event sources, etc). The default method merely clears out the alias.

=item _default

Provides a _default event handler to catch any POE event invocations that your
instance does not actually have. Will 'warn' about the nonexistent state. A big
difference from POE::Session is that the state and arguments are not rebundled 
upon invocation of this event handler. Instead the attempted state will be
available in the poe attribute and the arguments will be pass normally as an
array.

=back

=head1 METHOD MODIFIERS

=over 4

=item after 'BUILD

All of the magic for turning the constructed object into a Session happens in 
this method. If a BUILD is not provided, a stub exists to make sure this advice
is executed.

=back

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

=head1 AUTHOR

Copyright 2009 Nicholas Perez.
Released and distributed under the GPL.

=cut

1;
