package Moonpig::Test::Factory::Templates;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig;
use Moonpig::Util qw(class days dollars years);

use Data::GUID qw(guid_string);

use namespace::autoclean;

sub templates {
  my $dummy_xid = "consumer:test:dummy";
  my $b5g1_xid = "consumer:5y:test";

  return {
    dummy => sub {
      my ($name) = @_;
      return {
        roles => [ 'Consumer::Dummy' ],
        arg => {
          replacement_plan => [ get => '/nothing' ],
          xid              => $dummy_xid,
         },
       }
    },
    quick => sub {
      my ($name) = @_;
      return {
        roles => [ 'Consumer::ByTime::FixedAmountCharge' ],
        arg => {
          replacement_lead_time     => years(1000),
          charge_amount => dollars(100),
          cost_period => days(2),
          charge_description => 'quick consumer',
          replacement_plan   => [ get => '/consumer-template/quick' ],
        }};
    },

    fivemonth => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedAmountCharge', 't::Consumer::CouponCreator' ],
        arg   => {
          xid         => $b5g1_xid,
          replacement_lead_time     => days(7),
          charge_amount => dollars(500),
          cost_period => days(30 * 5),
          charge_description => 'long-term consumer',
          replacement_plan   => [ get => "/consumer-template/free_sixthmonth" ],

          coupon_class => class(qw(Coupon::FixedPercentage Coupon::RequiredTags)),
          coupon_args => {
            discount_rate => 1.00,
            target_tags   => [ $b5g1_xid, "coupon.b5g1" ],
            description   => "Buy five, get one free",
          },
        },
      }
    },
    free_sixthmonth => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedAmountCharge' ],
        arg   => {
          xid         => $b5g1_xid,
          replacement_lead_time     => days(7),
          charge_amount => dollars(100),
          cost_period => days(30),
          charge_description => 'free sixth-month consumer',
          replacement_plan   => [ get => "/consumer-template/$name" ],
          extra_invoice_charge_tags  => [ "coupon.b5g1" ],
        },
      },
    },
  };
}

1;
