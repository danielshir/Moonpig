package Moonpig::Role::Invoice::Quote;
# ABSTRACT: like an invoice, but doesn't expect to be paid

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Types qw(Time);
use Moose::Role;
use MooseX::SetOnce;

with(
  'Moonpig::Role::Invoice'
);

# requires qw(is_quote is_invoice);

# XXX better name here
has promoted_at => (
  is   => 'rw',
  isa  => Time,
  traits => [ qw(SetOnce) ],
  predicate => 'is_promoted',
);

sub mark_promoted {
  my ($self) = @_;
  confess sprintf "Can't promote open quote %s", $self->guid
    unless $self->is_closed;
  $self->promoted_at(Moonpig->env->now);
}

has quote_expiration_time => (
  is => 'rw',
  isa => Time,
  predicate => 'has_quote_expiration_time',
);

sub quote_has_expired {
  my ($self) = @_;
  $self->has_quote_expiration_time &&
    Moonpig->env->now->precedes($self->quote_expiration_time);
}

before _pay_charges => sub {
  my ($self, @args) = @_;
  confess sprintf "Can't pay charges on unpromoted quote %s", $self->guid
    unless $self->is_promoted;
};

sub first_consumer {
  my ($self) = @_;
  my @consumers = map $_->owner, $self->all_charges;
  my %consumers = map { $_->guid => $_ } @consumers;
  for my $consumer (@consumers) {
    $consumer->has_replacement && delete $consumers{$consumer->replacement->guid};
  }
  confess sprintf "Can't figure out the first consumer of quote %s", $self->guid
    unless keys %consumers == 1;
  my ($c) = values(%consumers);
  return $c
}

sub execute {
  my ($self) = @_;
  if ($self->quote_has_expired) {
    confess sprintf "Can't execute quote '%s'; it expired at %s\n",
      $self->guid, $self->quote_expiration_time->iso;
  }
  $self->mark_promoted;
  my $first_consumer = $self->first_consumer;
  my $active_consumer =
    $self->ledger->active_consumer_for_xid( $first_consumer->xid );

  if ($active_consumer) {
    $active_consumer->replacement($first_consumer);
  } else {
    $first_consumer->become_active;
  }
}

1;

