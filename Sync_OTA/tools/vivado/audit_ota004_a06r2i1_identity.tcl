# Diagnostic only. Never changes a design or accepts an alternate identity.
proc ota_i1_emit {f kind object property status actual expected comparison} {
 foreach field {object actual expected} {
  binary scan [encoding convertto utf-8 [set $field]] H* encoded
  set ${field}_hex $encoded
 }
 puts $f [join [list $kind $object_hex $property $status $actual_hex $expected_hex $comparison] "\t"]
 flush $f
 puts "OTA004_IDENTITY_OBSERVATION [list $kind $object $property $status $actual $expected $comparison]"
 flush stdout
}
proc ota_a06r2i1_identity {out} {
 set f [open [file join $out identity_observation.tsv] {WRONLY CREAT EXCL}]
 fconfigure $f -translation lf -encoding utf-8
 puts $f "kind\tobject_utf8_hex\tproperty\tquery_status\tactual_utf8_hex\texpected_utf8_hex\tcomparison"
 flush $f
 set designCode [catch {current_design} design designOptions]
 ota_i1_emit $f OBJECT {} current_design $designCode $design {} NOT_COMPARED
 if {$designCode || [llength $design]!=1} {
  ota_i1_emit $f GUARD $design EXACT_A06R2_CONDITION NOT_EVALUABLE {} {} QUERY_ERROR
  close $f
  error "identity diagnostic cannot get one current_design object"
 }
 # Both properties are read independently before any comparison/guard.
 set nameCode [catch {get_property NAME $design} actualName nameOptions]
 set partCode [catch {get_property PART $design} actualPart partOptions]
 set expectedName sync_ota_top
 set expectedPart xcvu11p-flgb2104-2-e
 set nameComparison QUERY_ERROR
 set partComparison QUERY_ERROR
 if {!$nameCode} {set nameComparison [expr {$actualName eq $expectedName}]}
 if {!$partCode} {set partComparison [expr {$actualPart eq $expectedPart}]}
 ota_i1_emit $f PRIMARY $design NAME $nameCode $actualName $expectedName $nameComparison
 ota_i1_emit $f PRIMARY $design PART $partCode $actualPart $expectedPart $partComparison
 # Separate read-only property inventory helps identify the proper top-module
 # identity later. It never supplies a fallback to the original guard.
 set listCode [catch {list_property $design} propertyNames listOptions]
 ota_i1_emit $f CONTEXT $design list_property $listCode $propertyNames {} NOT_COMPARED
 if {!$listCode} {
  foreach property [lsort $propertyNames] {
   if {[regexp -nocase {(^CLASS$|TOP|REF_NAME|DESIGN_MODE)} $property]} {
    set queryCode [catch {get_property $property $design} value options]
    ota_i1_emit $f CONTEXT $design $property $queryCode $value {} NOT_COMPARED
   }
  }
 }
 if {$nameCode || $partCode} {
  ota_i1_emit $f GUARD $design EXACT_A06R2_CONDITION NOT_EVALUABLE {} {} QUERY_ERROR
  close $f
  error "identity diagnostic NAME/PART query failed; raw results preserved"
 }
 # Same exact string conditions and literals as frozen A06R2 line16.
 set mismatch [expr {$actualName ne "sync_ota_top" || $actualPart ne "xcvu11p-flgb2104-2-e"}]
 ota_i1_emit $f GUARD $design EXACT_A06R2_CONDITION 0 $mismatch 0 [expr {!$mismatch}]
 ota_i1_emit $f COMPLETE $design DIAGNOSTIC_OBSERVATIONS_ONLY 0 1 {} NOT_QUALIFICATION
 close $f
 if {$mismatch} {error "wrong existing DCP design identity"}
 return ORIGINAL_GUARD_MATCHED_DIAGNOSTIC_ONLY
}
