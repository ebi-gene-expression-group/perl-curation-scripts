# Perl curation scripts
Perl-based scripts for ArrayExpress and Expression Atlas curation

## Purpose

The scripts are used by ArrayExpress and Expression Atlas curators for validating and processing experiments and array designs in MAGE-TAB format.


## Installation notes
Using the scripts relies on the [perl-atlas-modules](https://github.com/ebi-gene-expression-group/perl-atlas-modules) being installed. This can most easily be achieved using the [bioconda package](https://anaconda.org/bioconda/perl-atlas-modules).

Some parameters in the configuration file [ArrayExpressSiteConfig.yml](https://github.com/ebi-gene-expression-group/perl-atlas-modules/blob/develop/supporting_files/ArrayExpressSiteConfig.yml.default) need to be modified after installation in order to run the validation scripts:

`ADF_CHECKED_LIST` and `ATLAS_EXPT_CHECKED_LIST` (or `SKIP_CHECKED_LIST_FILES`)<br>
`ADF_DB_PATTERN_FILE`<br>
`ONTO_TERMS_LIST`

Many scripts also interact with the submissions tracking MySQL database. For this, the following parameters in the ArrayExpressSiteConfig.yml need to be set.

For connecting to the DB:<br>
`AUTOSUBS_DSN`<br>
`AUTOSUBS_USERNAME`<br>
`AUTOSUBS_PASSWORD`<br>

For running the checker daemon and processing submissions/ADFs:<br>
`AUTOSUBMISSIONS_FILEBASE`<br>
`AUTOSUBS_CURATOR_EMAIL`<br>
`AE2_LOAD_DIR`<br>
`AUTOSUBS_ADMIN` (email address)<br>
`AUTOSUBS_ADMIN_USERNAME` (username of the user that will be running the daemon)

## Usage examples

### MAGE-TAB file validation

```
validate_magetab.pl -i path/to/idf.txt -d path/to/sdrf/and/data -c
```
This calls MAGE-TAB format validation, curation and data file checks, and Atlas eligibility checks

```
validate_magetab.pl -i /path/to/idf.txt -d path/to/sdrf -x
```
With these options run MAGE-TAB format and AE loading checks only (no data file, curation or Atlas checks are triggered)


### MAGE-TAB checker daemon

```
launch_tracking_daemons.pl -k
```
Kill all running daemons

```
launch_tracking_daemons.pl -p MAGE-TAB
```
Start up a MAGE-TAB checker daemon that checks MAGE-TAB submissions marked as "Waiting" in the submissions tracking database

```
single_use_tracking_daemon.pl -p MAGE-TAB -s
```
Run the MAGE-TAB checker once to process all eligible experiments and then quit (no tracking of instance in the DB)


### Manually insert an array design

```
magetab_insert_array.pl -f adf_file_name.txt -l username
```
This inserts a new array design file (ADF) into the submissions tracking DB and assigns it the next available accession number and triggers the ADF validation
