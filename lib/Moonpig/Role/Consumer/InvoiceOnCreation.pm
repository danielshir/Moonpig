package Moonpig::Role::Consumer::InvoiceOnCreation;

use Moose::Role;

use List::MoreUtils qw(natatime);

use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(ArrayRef);

with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Behavior::EventHandlers;

requires 'invoice_costs';

implicit_event_handlers {
  return {
    created => {
      'initial-invoice' => Moonpig::Events::Handler::Method->new(
        method_name => '_invoice',
      ),
    },
  };
};

# For any given date, what do we think the total costs of ownership for this
# consumer are?  Example:
# [ 'basic account' => dollars(50), 'allmail' => dollars(20), 'support' => .. ]
# This is an arrayref so we can have ordered line items for display.
requires 'costs_on';

has extra_invoice_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub invoice_charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_invoice_charge_tags} ]
}

sub _invoice {
  my ($self) = @_;

  my $invoice = $self->ledger->current_invoice;

  my @costs = $self->invoice_costs();

  my $iter = natatime 2, @costs;

  while (my ($desc, $amt) = $iter->()) {
    $invoice->add_charge(
      class( "InvoiceCharge::Bankable" )->new({
        description => $desc,
        amount      => $amt,
        tags        => $self->invoice_charge_tags,
        consumer    => $self,
      }),
    );
  }
}

1;