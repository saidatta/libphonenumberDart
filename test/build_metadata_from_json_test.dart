@TestOn("!vm")
import "package:test/test.dart";

import "package:maui_frontend/model/phonenumber/build_metadata_from_json.dart";
import "package:collection/equality.dart";

void main() {
  //testProcessPhoneNumberDescElement();
  testGetObject();
}

void testProcessPhoneNumberDescElement() {
  BuildMetaDataFromJSON bmd = new BuildMetaDataFromJSON();
  group(("processPhoneNumberDescElement"), () {
    test("testing invalidType", () {
      PhoneNumberDesc generalDesc = new PhoneNumberDesc();
      Map territoryElement = {"territory": {}};
      PhoneNumberDesc phoneNumberDesc;

      phoneNumberDesc = bmd.processPhoneNumberDescElement(generalDesc, territoryElement, "invalidType", false);
      expect(phoneNumberDesc.possibleNumberPattern, "NA");
      expect(phoneNumberDesc.nationalNumberPattern, "NA");
    });

    test("testProcessPhoneNumberDescElementMergesWithGeneralDesc", () {
      PhoneNumberDesc generalDesc = new PhoneNumberDesc();
      generalDesc.possibleNumberPattern = "\\d{6}";
      Map territoryElement = {
        "territory": {"fixedLine": {}}
      };
      PhoneNumberDesc phoneNumberDesc;

      phoneNumberDesc = bmd.processPhoneNumberDescElement(generalDesc, territoryElement, "fixedLine", false);
      expect(phoneNumberDesc.possibleNumberPattern, "\\d{6}");
    });

    test("testProcessPhoneNumberDescElementOverridesGeneralDesc", () {
      PhoneNumberDesc generalDesc = new PhoneNumberDesc();
      generalDesc.possibleNumberPattern = "\\d{8}";
      Map territoryElement = {
        "territory": {
          "fixedLine": {
            "possibleNumberPattern": {"\$": "\\d{6}"}
          }
        }
      };
      PhoneNumberDesc phoneNumberDesc;

      phoneNumberDesc = bmd.processPhoneNumberDescElement(generalDesc, territoryElement, "fixedLine", false);
      expect(phoneNumberDesc.possibleNumberPattern, "\\d{6}");
    });

    test("testProcessPhoneNumberDescElementHandlesLiteBuild", () {
      PhoneNumberDesc generalDesc = new PhoneNumberDesc();
      Map territoryElement = {
        "territory": {
          "fixedLine": {
            "exampleNumber": {"\$": "01 01 01 01"}
          }
        }
      };
      PhoneNumberDesc phoneNumberDesc;

      phoneNumberDesc = bmd.processPhoneNumberDescElement(generalDesc, territoryElement, "fixedLine", true);
      expect(phoneNumberDesc.exampleNumber, null);
    });

    test("testProcessPhoneNumberDescOutputsExampleNumberByDefault", () {
      PhoneNumberDesc generalDesc = new PhoneNumberDesc();
      Map territoryElement = {
        "territory": {
          "fixedLine": {
            "exampleNumber": {"\$": "01 01 01 01"}
          }
        }
      };
      PhoneNumberDesc phoneNumberDesc;

      phoneNumberDesc = bmd.processPhoneNumberDescElement(generalDesc, territoryElement, "fixedLine", false);
      expect(phoneNumberDesc.exampleNumber, "01 01 01 01");
    });

    test("testProcessPhoneNumberDescRemovesWhiteSpacesInPatterns", () {
      PhoneNumberDesc generalDesc = new PhoneNumberDesc();
      Map territoryElement = {
        "territory": {
          "fixedLine": {
            "possibleNumberPattern": {"\$": "\t \\d { 6 }"}
          }
        }
      };
      PhoneNumberDesc phoneNumberDesc = bmd.processPhoneNumberDescElement(generalDesc, territoryElement, "fixedLine", false);
      expect(phoneNumberDesc.possibleNumberPattern, "\\d{6}");
    });
  });

  group(("Tests setRelevantDescPatterns()."), () {
    test("testSetRelevantDescPatternsSetsSameMobileAndFixedLinePattern", () {
      Map territoryElement = {
        "territory": {
          "@countryCode": "33",
          "fixedLine": {
            "nationalNumberPattern": {"\$": "\\d{6}"}
          },
          "mobile": {
            "nationalNumberPattern": {"\$": "\\d{6}"}
          }
        }
      };
      PhoneMetadata pmd = new PhoneMetadata();
      bmd.setRelevantDescPatterns(pmd, territoryElement, false /*LiteBuild*/, false /*isShortNumberMetaData*/);
      expect(pmd.sameMobileAndFixedLinePattern, true);
    });

    test("testSetRelevantDescPatternsSetsAllDescriptionsForRegularLengthNumbers", () {
      Map territoryElement = {
        "territory": {
          "@countryCode": "33",
          "fixedLine": {
            "nationalNumberPattern": {"\$": "\\d{1}"}
          },
          "mobile": {
            "nationalNumberPattern": {"\$": "\\d{2}"}
          },
          "pager": {
            "nationalNumberPattern": {"\$": "\\d{3}"}
          },
          "tollFree": {
            "nationalNumberPattern": {"\$": "\\d{4}"}
          },
          "premiumRate": {
            "nationalNumberPattern": {"\$": "\\d{5}"}
          },
          "sharedCost": {
            "nationalNumberPattern": {"\$": "\\d{6}"}
          },
          "personalNumber": {
            "nationalNumberPattern": {"\$": "\\d{7}"}
          },
          "voip": {
            "nationalNumberPattern": {"\$": "\\d{8}"}
          },
          "uan": {
            "nationalNumberPattern": {"\$": "\\d{9}"}
          }
        }
      };

      PhoneMetadata pmd = new PhoneMetadata();
      bmd.setRelevantDescPatterns(pmd, territoryElement, false /*LiteBuild*/, false /*isShortNumberMetaData*/);
      expect(pmd.fixedLine.nationalNumberPattern, "\\d{1}");
      expect(pmd.mobile.nationalNumberPattern, "\\d{2}");
      expect(pmd.pager.nationalNumberPattern, "\\d{3}");
      expect(pmd.tollFree.nationalNumberPattern, "\\d{4}");
      expect(pmd.premiumRate.nationalNumberPattern, "\\d{5}");
      expect(pmd.sharedCost.nationalNumberPattern, "\\d{6}");
      expect(pmd.personalNumber.nationalNumberPattern, "\\d{7}");
      expect(pmd.voip.nationalNumberPattern, "\\d{8}");
      expect(pmd.uan.nationalNumberPattern, "\\d{9}");
    });

    test("testSetRelevantDescPatternsSetsAllDescriptionsForShortNumbers", () {
      Map territoryElement = {
        "territory": {
          "@id": "FR",
          "tollFree": {
            "nationalNumberPattern": {"\$": "\\d{1}"}
          },
          "standardRate": {
            "nationalNumberPattern": {"\$": "\\d{2}"}
          },
          "premiumRate": {
            "nationalNumberPattern": {"\$": "\\d{3}"}
          },
          "shortCode": {
            "nationalNumberPattern": {"\$": "\\d{4}"}
          },
          "carrierSpecific": {
            "nationalNumberPattern": {"\$": "\\d{5}"}
          }
        }
      };

      PhoneMetadata pmd = new PhoneMetadata();
      bmd.setRelevantDescPatterns(pmd, territoryElement, false /*LiteBuild*/, true /*isShortNumberMetaData*/);
      expect(pmd.tollFree.nationalNumberPattern, "\\d{1}");
      expect(pmd.standardRate.nationalNumberPattern, "\\d{2}");
      expect(pmd.premiumRate.nationalNumberPattern, "\\d{3}");
      expect(pmd.shortCode.nationalNumberPattern, "\\d{4}");
      expect(pmd.carrierSpecific.nationalNumberPattern, "\\d{5}");
    });
  });
}

void testGetObject() {
  BuildMetaDataFromJSON bmd = new BuildMetaDataFromJSON();
  group("Testing getObject Method", () {
    test("getObject: Non-Existent Key", () {
      Map t1 = {"item1": "value1"};
      expect(bmd.getObject("xyz", t1), isNull);
    });

    test("getObject(): Testing 1 string map", () {
      Map t1 = {"item1": "value1"};
      expect(bmd.getObject("item1", t1), "value1");
    });

    test("getObject", () {
      Map t1 = {"item1": "value1", "item2":"value2"};
      expect(bmd.getObject("item2", t1), "value2");
    });

    test("getObject(): Testing 2 Nested Maps", () {
      Map t1 = {"item1": {"n1":"v1"},"item2":{"n2":"v2"}};
      expect(bmd.getObject("n1", t1), "v1");
    });

    test("getObject(): Testing 1 String + 1 Map", () {
      Map t1 = {"item1": {"n1":"v1"},"item2":"value2"};
      Map ans = {"n1":"v1"};
      MapEquality mq = new MapEquality();
      expect(mq.equals(bmd.getObject("item1", t1), ans), true);
    });

    test("getObject(): Testing Nested Map", () {
      Map t1 = {"item1": {"n1":{"x1":"v1"}},"item2":"value2"};
      MapEquality mq = new MapEquality();
      expect(bmd.getObject("x1", t1), "v1");
    });
  });
}
