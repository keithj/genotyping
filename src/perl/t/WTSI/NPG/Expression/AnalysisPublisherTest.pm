
use utf8;

package WTSI::NPG::Expression::AnalysisPublisherTest;

use strict;
use warnings;
use DateTime;

use base qw(WTSI::NPG::Test);
use Test::More tests => 10;
use Test::Exception;

Log::Log4perl::init('./etc/log4perl_tests.conf');

BEGIN { use_ok('WTSI::NPG::Expression::AnalysisPublisher') };

use WTSI::NPG::Expression::ChipLoadingManifestV2;
use WTSI::NPG::Expression::AnalysisPublisher;
use WTSI::NPG::iRODS;

my $data_path = './t/expression_analysis_publisher';
my $manifest_path = "$data_path/manifest.txt";
my $sample_data_path = "$data_path/data/samples/infinium";
my $analysis_data_path = "$data_path/data/analysis";

my @data_files_10digit = qw(0123456789_A_Grn.idat
                            0123456789_A_Grn.xml
                            0123456789_B_Grn.idat
                            0123456789_B_Grn.xml);
my @data_files_12digit = qw(012345678901_C_Grn.idat
                            012345678901_C_Grn.xml);

my @sample_ids_10digit = qw(QC1Hip-86 QC1Hip-86
                            QC1Hip-87 QC1Hip-87);
my @sample_ids_12digit = qw(QC1Hip-88 QC1Hip-88);

my @beadchip_sections_10digit = qw(A A
                                   B B);
my @beadchip_sections_12digit = qw(C C);

my $study_id = 0;
my $irods_tmp_coll;

my $pid = $$;
my $test_num = 0;

sub make_fixture : Test(setup) {
  my $irods = WTSI::NPG::iRODS->new;
  $irods_tmp_coll =
    $irods->add_collection("ExpressionAnalysisPublisherTest.$pid.$test_num");
  $test_num++;

  $irods->put_collection($sample_data_path, $irods_tmp_coll);

  for (my $i = 0; $i < scalar @data_files_10digit; $i++) {
    my $irods_path = "$irods_tmp_coll/infinium/" . $data_files_10digit[$i];
    my $obj = WTSI::NPG::iRODS::DataObject->new($irods, $irods_path)->absolute;
    $obj->add_avu('dcterms:identifier', $sample_ids_10digit[$i]);
    $obj->add_avu('beadchip', '0123456789');
    $obj->add_avu('beadchip_section', $beadchip_sections_10digit[$i]);
    $obj->add_avu('study_id', $study_id);
  }

  for (my $i = 0; $i < scalar @data_files_12digit; $i++) {
    my $irods_path = "$irods_tmp_coll/infinium/" . $data_files_12digit[$i];
    my $obj = WTSI::NPG::iRODS::DataObject->new($irods, $irods_path)->absolute;
    $obj->add_avu('dcterms:identifier', $sample_ids_12digit[$i]);
    $obj->add_avu('beadchip', '012345678901');
    $obj->add_avu('beadchip_section', $beadchip_sections_12digit[$i]);
    $obj->add_avu('study_id', $study_id);
  }
}

sub teardown : Test(teardown) {
  my $irods = WTSI::NPG::iRODS->new;
  $irods->remove_collection($irods_tmp_coll);
}

sub require : Test(1) {
  require_ok('WTSI::NPG::Expression::AnalysisPublisher');
};

sub constructor : Test(1) {
  my $publication_time = DateTime->now;
  my $manifest =  WTSI::NPG::Expression::ChipLoadingManifestV2->new
    (file_name => $manifest_path);

  new_ok('WTSI::NPG::Expression::AnalysisPublisher',
         [analysis_directory => $analysis_data_path,
          manifest           => $manifest,
          publication_time   => $publication_time,
          sample_archive     => $sample_data_path]);
}

sub publish : Test(7) {
  my $irods = WTSI::NPG::iRODS->new;
  my $publish_dest = $irods_tmp_coll;
  my $sample_archive = "$irods_tmp_coll/infinium";
  my $publication_time = DateTime->now;

  my $manifest =  WTSI::NPG::Expression::ChipLoadingManifestV2->new
    (file_name => $manifest_path);

  my $publisher = WTSI::NPG::Expression::AnalysisPublisher->new
    (analysis_directory => $analysis_data_path,
     manifest           => $manifest,
     publication_time   => $publication_time,
     sample_archive     => $sample_archive);

  my $analysis_uuid = $publisher->publish($publish_dest);
  ok($analysis_uuid, "Yields analysis UUID");

  my @analysis_data =
    $irods->find_collections_by_meta($irods_tmp_coll,
                                     [analysis_uuid => $analysis_uuid]);
  cmp_ok(scalar @analysis_data, '==', 1, "A single analysis annotated");

  my @no_norm_profiles =
    $irods->find_objects_by_meta($irods_tmp_coll,
                                 [normalisation_method => 'none'],
                                 [summary_type         => 'probe'],
                                 [summary_group        => 'sample']);
  cmp_ok(scalar @no_norm_profiles, '==', 1, "A single no-norm profile");

  my @cubic_norm_profiles =
    $irods->find_objects_by_meta($irods_tmp_coll,
                                 [normalisation_method => 'cubic spline'],
                                 [summary_type         => 'probe'],
                                 [summary_group        => 'sample']);
  cmp_ok(scalar @cubic_norm_profiles, '==', 1, "A single cubic norm profile");

  my @quantile_norm_profiles =
    $irods->find_objects_by_meta($irods_tmp_coll,
                                 [normalisation_method => 'quantile'],
                                 [summary_type         => 'probe'],
                                 [summary_group        => 'sample']);
  cmp_ok(scalar @quantile_norm_profiles, '==', 1,
         "A single quantile norm profile");

  my @profile_annotation =
    $irods->find_objects_by_meta($irods_tmp_coll,
                                 [summary_type => 'annotation']);
  cmp_ok(scalar @profile_annotation, '==', 1,
         "A single annotation file");

  my @sample_data =
    $irods->find_objects_by_meta("$irods_tmp_coll/infinium",
                                 [analysis_uuid => $analysis_uuid]);

  my @expected_sample_data = sort map { "$irods_tmp_coll/infinium/$_" }
    (@data_files_10digit, @data_files_12digit);

  is_deeply(\@sample_data, \@expected_sample_data,
            "Annotated sample objects match") or diag explain \@sample_data;
}

1;
