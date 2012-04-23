package Moonpig::Role::InvoiceCharge;
use Moose::Role;
# ABSTRACT: a charge placed on an invoice

with(
  'Moonpig::Role::Charge',
  'Moonpig::Role::ConsumerComponent',
  'Moonpig::Role::HandlesEvents',
);

use namespace::autoclean;
use Moonpig::Behavior::EventHandlers;
use Moonpig::Types qw(Time);
use MooseX::SetOnce;

has abandoned_date => (
  is => 'ro',
  isa => Time,
  predicate => 'is_abandoned',
  writer    => '__set_abandoned_date',
  traits => [ qw(SetOnce) ],
);

sub counts_toward_total { ! $_[0]->is_abandoned }

sub mark_abandoned {
  my ($self) = @_;
  $self->__set_abandoned_date( Moonpig->env->now );
}

has executed_at => (
  is  => 'ro',
  isa => Time,
  predicate => 'is_executed',
  writer    => '__set_executed_at',
  traits    => [ qw(SetOnce) ],
);

implicit_event_handlers {
  return {
    'paid' => {
      'default' => Moonpig::Events::Handler::Noop->new,
    },
  }
};

1;
