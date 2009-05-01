package POE::Session::Moose;
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
    => where { $_->does('POE::Session::Moose') };

has heap =>
(
    is => 'rw',
    isa => 'Any'
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
    my ($self, $state) = @_;
    my $string = $self->alias // $self;
    warn "Event nonexistent '$state' delivered to $string";
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

            # also weed out any of the non-event methods
            if ($name =~ /post|yield|call|BUILD|DOES|_invoke_state|clear_alias|_register_state|meta|does|new|DESTROY|DEMOLISHALL|_clone_self|\(/)
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
            
            my $return = $default->execute($self, $state, @$etc);
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

1;
