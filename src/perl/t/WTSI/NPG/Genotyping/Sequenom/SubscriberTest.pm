use utf8;

package WTSI::NPG::Genotyping::Sequenom::SubscriberTest;

use strict;
use warnings;
use DateTime;
use List::AllUtils qw(uniq);

use base qw(Test::Class);
use Test::More tests => 8;
use Test::Exception;

Log::Log4perl::init('./etc/log4perl_tests.conf');

BEGIN { use_ok('WTSI::NPG::Genotyping::Sequenom::Subscriber') };

use WTSI::NPG::Genotyping::Sequenom::Subscriber;
use WTSI::NPG::Genotyping::Sequenom::AssayDataObject;
use WTSI::NPG::iRODS;
use WTSI::NPG::iRODS::DataObject;

my $data_path = './t/sequenom_subscriber';
my @assay_resultset_files = qw(sequenom_001.csv sequenom_002.csv
                               sequenom_003.csv sequenom_004.csv);
my @sample_identifiers = qw(sample_foo sample_foo sample_bar sample_baz);
my @sample_plates = qw(plate1234 plate1234 plate5678 plate1234);
my @sample_wells = qw(S01 S02 S03 S04);
my $non_unique_identifier = 'ABCDEFGHI';

my $reference_name = 'Homo_sapiens (1000Genomes)';
my $snpset_name = 'W30467_GRCh37';
my $snpset_file = 'W30467_snp_set_info_GRCh37.tsv';

my $irods_tmp_coll;

my $pid = $$;

sub make_fixture : Test(setup) {
  my $irods = WTSI::NPG::iRODS->new;
  $irods_tmp_coll = "SequenomSubscriberTest.$pid";
  $irods->add_collection($irods_tmp_coll);
  $irods->add_object("$data_path/$snpset_file", "$irods_tmp_coll/$snpset_file");

  my $snpset_obj = WTSI::NPG::iRODS::DataObject->new
    ($irods,"$irods_tmp_coll/$snpset_file")->absolute;
  $snpset_obj->add_avu('fluidigm_plex', $snpset_name);
  $snpset_obj->add_avu('reference_name', $reference_name);

  foreach my $i (0..3) {
    my $file = $assay_resultset_files[$i];
    $irods->add_object("$data_path/$file", "$irods_tmp_coll/$file");
    my $resultset_obj = WTSI::NPG::iRODS::DataObject->new
      ($irods,"$irods_tmp_coll/$file")->absolute;
    $resultset_obj->add_avu('sequenom_plex', $snpset_name);
    $resultset_obj->add_avu('sequenom_plate', $sample_plates[$i]);
    $resultset_obj->add_avu('sequenom_well', $sample_wells[$i]);
    $resultset_obj->add_avu('dcterms:identifier', $sample_identifiers[$i]);
    $resultset_obj->add_avu('dcterms:identifier', $non_unique_identifier);
  }
}

sub teardown : Test(teardown) {
  my $irods = WTSI::NPG::iRODS->new;
  $irods->remove_collection($irods_tmp_coll);
}


sub require : Test(1) {
  require_ok('WTSI::NPG::Genotyping::Sequenom::Subscriber');
}

sub constructor : Test(1) {
  my $irods = WTSI::NPG::iRODS->new;

  new_ok('WTSI::NPG::Genotyping::Sequenom::Subscriber',
         [irods          => $irods,
          data_path      => $irods_tmp_coll,
          reference_path => $irods_tmp_coll,
          reference_name => $reference_name,
          snpset_name    => $snpset_name]);
}

sub get_assay_resultsets : Test(5) {
  my $irods = WTSI::NPG::iRODS->new;
  my $resultsets1 = WTSI::NPG::Genotyping::Sequenom::Subscriber->new
    (irods          => $irods,
     data_path      => $irods_tmp_coll,
     reference_path => $irods_tmp_coll,
     reference_name => $reference_name,
     snpset_name    => $snpset_name)->get_assay_resultsets
       ([uniq @sample_identifiers]);

  cmp_ok(scalar keys %$resultsets1, '==', 3, 'Assay resultsets for 3 samples');
  cmp_ok(scalar @{$resultsets1->{sample_foo}}, '==', 2,
         '2 of 4 results for 1 sample');
  cmp_ok(scalar @{$resultsets1->{sample_bar}}, '==', 1,
         '1 of 4 results for 1 sample');

  dies_ok {
    WTSI::NPG::Genotyping::Sequenom::Subscriber->new
        (irods          => $irods,
         data_path      => $irods_tmp_coll,
         reference_path => $irods_tmp_coll,
         reference_name => $reference_name,
         snpset_name    => $snpset_name)->get_assay_resultsets
           ([$non_unique_identifier]);
  } 'Fails when query finds results for >1 sample';

  ok(defined WTSI::NPG::Genotyping::Sequenom::Subscriber->new
     (irods          => $irods,
      data_path      => $irods_tmp_coll,
      reference_path => $irods_tmp_coll,
      reference_name => $reference_name,
      snpset_name    => $snpset_name)->get_assay_resultsets
     ([map { 'X' . $_ } 1 .. 100]), "'IN' query of 100 args");
}