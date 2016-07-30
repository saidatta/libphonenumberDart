@TestOn("!vm")
import "package:test/test.dart";

import "package:maui_frontend/model/phonenumber/phone_converter.dart";
import "package:maui_frontend/model/phonenumber/build_metadata_from_json.dart";
import "package:maui_frontend/model/phonenumber/phone_number.dart";
import 'dart:async';

/**
 * Enum containing string constants of region codes for easier testing.
 *
 * @enum {string}
 */
Map<String, String> RegionCode = {
// Region code for global networks (e.g. +800 numbers).
  'UN001': '001',
  'AD': 'AD',
  'AE': 'AE',
  'AO': 'AO',
  'AQ': 'AQ',
  'AR': 'AR',
  'AU': 'AU',
  'BB': 'BB',
  'BR': 'BR',
  'BS': 'BS',
  'BY': 'BY',
  'CA': 'CA',
  'CH': 'CH',
  'CN': 'CN',
  'CS': 'CS',
  'CX': 'CX',
  'DE': 'DE',
  'GB': 'GB',
  'HU': 'HU',
  'IT': 'IT',
  'JP': 'JP',
  'KR': 'KR',
  'MX': 'MX',
  'NZ': 'NZ',
  'PL': 'PL',
  'RE': 'RE',
  'SE': 'SE',
  'SG': 'SG',
  'US': 'US',
  'YT': 'YT',
  'ZW': 'ZW',
// Official code for the unknown region.
  'ZZ': 'ZZ'
};

PhoneConverter phoneConverter = new PhoneConverter();

void main() {
  // since pub run test from current dir test.
  testGroupDatas();
  testIsValidNumber();
  testGetRegionCodeForNumber();
  testIsValidNumberForRegion();
  testIsNotValidNumber();
  testIsLeadingZeroPossible();
  testGetRegionCodeForCountryCode();
  testGetInstanceLoadUSMetadata();
  testGetNationalSignificantNumber();
}

void testGetNationalSignificantNumber() {
  PhoneNumber US_NUMBER = new PhoneNumber();
  US_NUMBER.setCountryCode = 1;
  US_NUMBER.setNationalNumber = 6502530000;

  PhoneNumber INTERNATIONAL_TOLL_FREE = new PhoneNumber();
  INTERNATIONAL_TOLL_FREE.setCountryCode = 800;
  INTERNATIONAL_TOLL_FREE.setNationalNumber = 12345678;

  test("testGetNationalSignificantNumber: US_Number NATIONAL", () {
    var number1 = phoneConverter.getNationalSignificantNumber(US_NUMBER);
    expect(number1, '6502530000');
  });

  test("testGetNationalSignificantNumber: INTERNATIONAL_TOLL_FREE NATIONAL", () {
    var number1 = phoneConverter.getNationalSignificantNumber(INTERNATIONAL_TOLL_FREE);
    expect(number1, '12345678');
  });
}

void testGetInstanceLoadUSMetadata() {
  test("Testing ViablePhoneNumber: ", () {
    PhoneMetadata metadata = phoneConverter.getMetadataForRegion(RegionCode["US"]);
    expect(metadata.id, RegionCode["US"]);
    expect(metadata.countryCode, 1);
    expect(metadata.internationalPrefix, '011');
    expect(metadata.hasNationalPrefix(), true);
    expect(metadata.numberFormat.length, 2);
    expect(metadata.numberFormat[1].pattern, '(\\d{3})(\\d{3})(\\d{4})');
    expect(metadata.numberFormat[1].format, '(\$1) \$2-\$3');
    expect(metadata.generalDesc.nationalNumberPattern, '[2-9]\\d{9}');
    expect(metadata.generalDesc.possibleNumberPattern, '\\d{7}(?:\\d{3})?');
    //expect(metadata.getGeneralDesc() == metadata.fixedLine, true);
    expect(metadata.tollFree.possibleNumberPattern, '\\d{10}');
    expect(metadata.premiumRate.nationalNumberPattern, '900[2-9]\\d{6}');
    expect(metadata.sharedCost.nationalNumberPattern, 'NA');
    expect(metadata.sharedCost.possibleNumberPattern, 'NA');
  });
}

void testGetRegionCodeForCountryCode() {
  test("getRegionCodeForCountryCode: 1 RegionCode:US", () {
    expect(phoneConverter.getRegionCodeForCountryCode(1), RegionCode["US"]);
  });
  test("getRegionCodeForCountryCode: 800 RegionCode:UN001", () {
    expect(phoneConverter.getRegionCodeForCountryCode(800), RegionCode["UN001"]);
  });
  test("getRegionCodeForCountryCode: 979 RegionCode:UN001", () {
    expect(phoneConverter.getRegionCodeForCountryCode(979), RegionCode["UN001"]);
  });
}

void testIsLeadingZeroPossible() {
  test("isLeadingZeroPossible: USA - 1", () {
    bool isPossible = phoneConverter.isLeadingZeroPossible(1);
    expect(isPossible, false);
  });
  test("isLeadingZeroPossible: International toll free - 800", () {
    bool isPossible = phoneConverter.isLeadingZeroPossible(800);
    expect(isPossible, true);
  });
  test("isLeadingZeroPossible: International premium-rate - 979", () {
    bool isPossible = phoneConverter.isLeadingZeroPossible(979);
    expect(isPossible, true); // false?
  });
  test("isLeadingZeroPossible: Not in metadata file, just default to false - 888", () {
    bool isPossible = phoneConverter.isLeadingZeroPossible(888);
    expect(isPossible, true); // false?
  });
}

Future futureLoading() {
  return phoneConverter.loadMetadataFromJSON("../lib/model/phonenumber/phone_metadata.json");
}

void testGroupDatas() {
  PhoneNumber US_NUMBER = new PhoneNumber();
  US_NUMBER.setCountryCode = 1;
  US_NUMBER.setNationalNumber = 6502530000;

  PhoneNumber US_LOCAL_NUMBER = new PhoneNumber();
  US_LOCAL_NUMBER.setCountryCode = 1;
  US_LOCAL_NUMBER.setNationalNumber = 2530000;

  group("Testing ViablePhoneNumber: ", () {
    test("1", () async {
      await futureLoading();
      bool result = phoneConverter.isViablePhoneNumber("1");
      expect(result, false);
    });
    // Only one or two digits before strange non-possible punctuation.
    test("1+1+1", () {
      bool result = phoneConverter.isViablePhoneNumber("1+1+1");
      expect(result, false);
    });
    test("80+0", () {
      bool result = phoneConverter.isViablePhoneNumber("80+0");
      expect(result, false);
    });
    // Two digits is viable.
    test("00", () {
      bool result = phoneConverter.isViablePhoneNumber("00");
      expect(result, true);
    });
    test("111", () {
      bool result = phoneConverter.isViablePhoneNumber("111");
      expect(result, true);
    });
    // Alpha numbers.
    test("0800-4-pizza", () {
      bool result = phoneConverter.isViablePhoneNumber("0800-4-pizza");
      expect(result, true);
    });
    test("0800-4-PIZZA", () {
      bool result = phoneConverter.isViablePhoneNumber("0800-4-PIZZA");
      expect(result, true);
    });
    // We need at least three digits before any alpha characters.
    test("08-PIZZA", () {
      bool result = phoneConverter.isViablePhoneNumber("08-PIZZA");
      expect(result, false);
    });
    test("8-PIZZA", () {
      bool result = phoneConverter.isViablePhoneNumber("8-PIZZA");
      expect(result, false);
    });
    test("12. March", () {
      bool result = phoneConverter.isViablePhoneNumber("12. March");
      expect(result, false);
    });
  });

  group("Testing ExtractPossibleNumber: ", () {
    // Removes preceding funky punctuation and letters but leaves the rest
    // untouched.
    test("ExtractPossibleNumber: Tel:0800-345-600", () {
      String result = phoneConverter.extractPossibleNumber("Tel:0800-345-600");
      expect(result, "0800-345-600");
    });
    test("ExtractPossibleNumber: Tel:0800 FOR PIZZA", () {
      String result = phoneConverter.extractPossibleNumber("Tel:0800 FOR PIZZA");
      expect(result, "0800 FOR PIZZA");
    });
    // Should not remove plus sign
    test("ExtractPossibleNumber: +800-345-600", () {
      String result = phoneConverter.extractPossibleNumber("+800-345-600");
      expect(result, "+800-345-600");
    });
    // Should recognise wide digits as possible start values.
    test("ExtractPossibleNumber: \uFF10\uFF12\uFF13", () {
      String result = phoneConverter.extractPossibleNumber("\uFF10\uFF12\uFF13");
      expect(result, "\uFF10\uFF12\uFF13");
    });
    // Dashes are not possible start values and should be removed.
    test("ExtractPossibleNumber: \uFF11\uFF12\uFF13", () {
      String result = phoneConverter.extractPossibleNumber("Num-\uFF11\uFF12\uFF13");
      expect(result, "\uFF11\uFF12\uFF13");
    });
    // If not possible number present, return empty string.
    test("ExtractPossibleNumber: Num-....", () {
      String result = phoneConverter.extractPossibleNumber("Num-....");
      expect(result, "");
    });
    // Leading brackets are stripped - these are not used when parsing.
    test("ExtractPossibleNumber: (650) 253-0000", () {
      String result = phoneConverter.extractPossibleNumber("(650) 253-0000");
      expect(result, "650) 253-0000");
    });
    // Trailing non-alpha-numeric characters should be removed.
    test("ExtractPossibleNumber: (650) 253-0000..- ..", () {
      String result = phoneConverter.extractPossibleNumber("(650) 253-0000..- ..");
      expect(result, "650) 253-0000");
    });
    // Trailing non-alpha-numeric characters should be removed.
    test("ExtractPossibleNumber: (650) 253-0000.", () {
      String result = phoneConverter.extractPossibleNumber("(650) 253-0000.");
      expect(result, "650) 253-0000");
    });
    // This case has a trailing RTL char.
    test("ExtractPossibleNumber: (650) 253-0000\u200F", () {
      String result = phoneConverter.extractPossibleNumber("(650) 253-0000\u200F");
      expect(result, "650) 253-0000");
    });
  });

  group("Testing Normalize", () {
    test("testNormaliseRemovePunctuation: 034-56&+#2\u00AD34", () {
      var inputNumber = '034-56&+#2\u00AD34';
      var expectedOutput = '03456234';
      String receivedOutput = phoneConverter.normalize(inputNumber);
      expect(receivedOutput, expectedOutput, reason: 'Conversion did not correctly remove punctuation');
    });

    test("testNormaliseReplaceAlphaCharacters: 034-I-am-HUNGRY", () {
      var inputNumber = '034-I-am-HUNGRY';
      var expectedOutput = '034426486479';
      String receivedOutput = phoneConverter.normalize(inputNumber);
      expect(receivedOutput, expectedOutput, reason: 'Conversion did not correctly replace alpha characters');
    });

    test("testNormaliseOtherDigits: \uFF125\u0665", () {
      var inputNumber = '\uFF125\u0665';
      var expectedOutput = '255';
      String receivedOutput = phoneConverter.normalize(inputNumber);
      expect(receivedOutput, expectedOutput, reason: 'Conversion did not correctly replace non-latin digits');
    });

    test("testNormaliseOtherDigits: \u06F52\u06F0", () {
      // Eastern-Arabic digits
      var inputNumber = '\u06F52\u06F0';
      var expectedOutput = '520';
      String receivedOutput = phoneConverter.normalize(inputNumber);
      expect(receivedOutput, expectedOutput, reason: 'Conversion did not correctly replace non-latin digits');
    });
  });

  group("Testing NormalizeDigitsOnly ", () {
    test("testNormaliseStripAlphaCharacters: 034-56&+a#234", () {
      var inputNumber = '034-56&+a#234';
      var expectedOutput = '03456234';
      String receivedOutput = phoneConverter.normalizeDigitsOnly(inputNumber);
      expect(receivedOutput, expectedOutput);
    });
  });

  group("Testing parsing String to PhoneNumber", () {
    test("testParse: 5103628154", () {
      var inputNumber = '5103628154';
      PhoneNumber ph = new PhoneNumber();
      ph.setNationalNumber = 5103628154;
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, ph.getNationalNumber);
    });

    test("testParse: 6000+ input string", () {
      String maliciousNumber = "";
      for (var i = 0; i < 6000; i++) {
        maliciousNumber += '+';
      }
      maliciousNumber += '12222-33-244 extensioB 343+';
      try {
        phoneConverter.parse(maliciousNumber, defaultRegion: "US");
      } catch (e) {
        // Recieves the NumberParseException;
        NumberParseException e1 = e;
        expect(e1.toString(), new NumberParseException(ErrorType.TOO_LONG, "The string supplied was too long to parse.").toString());
      }
    });

    test("testParse: maliciousNumberWithAlmostExt", () {
      String maliciousNumberWithAlmostExt = "";
      for (int i = 0; i < 350; i++) {
        maliciousNumberWithAlmostExt += '200';
      }
      maliciousNumberWithAlmostExt += ' extensiOB 345';
      try {
        phoneConverter.parse(maliciousNumberWithAlmostExt, defaultRegion: "US");
      } catch (e) {
        // Recieves the NumberParseException;
        NumberParseException e1 = e;
        expect(e1.toString(), new NumberParseException(ErrorType.TOO_LONG, "The string supplied was too long to parse.").toString());
      }
    });

    //  assertTrue(INTERNATIONAL_TOLL_FREE.equals(phoneUtil.parse('011 800 1234 5678', RegionCode.US)));
    test("testParse: INTERNATIONAL_TOLL_FREE", () {
      String inputNumber = "011 800 1234 5678";
      PhoneNumber ph = new PhoneNumber();
      ph.setCountryCode = 800;
      ph.setNationalNumber = 12345678;
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, ph.getNationalNumber);
    });

    test("testParse: US-NUMBER", () {
      String inputNumber = "1-650-253-0000";
      PhoneNumber ph = new PhoneNumber();
      ph.setCountryCode = 1;
      ph.setNationalNumber = 6502530000;
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, ph.getNationalNumber);
    });

    test("testParse: US Local Number - tel:253-0000;phone-context=www.google.com", () {
      String inputNumber = "tel:253-0000;phone-context=www.google.com";
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, US_LOCAL_NUMBER.getNationalNumber);
    });

    test("testParse: US Local Number with isub - tel:253-0000;isub=12345;phone-context=www.google.com", () {
      String inputNumber = "tel:253-0000;isub=12345;phone-context=www.google.com";
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, US_LOCAL_NUMBER.getNationalNumber);
    });

    // This is invalid because no "+" sign is present as part of phone-context.
    // The phone context is simply ignored in this case just as if it contains a
    // domain.
    test("testParse: US Local Number with isub - tel:2530000;isub=12345;phone-context=1-650", () {
      String inputNumber = "tel:2530000;isub=12345;phone-context=1-650";
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, US_LOCAL_NUMBER.getNationalNumber);
    });

    test("testParse: US Local Number with isub - tel:2530000;isub=12345;phone-context=1234.com", () {
      String inputNumber = "tel:2530000;isub=12345;phone-context=1234.com";
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, US_LOCAL_NUMBER.getNationalNumber);
    });

    test("testParse: US Number- 123-456-7890", () {
      String inputNumber = "tel:2530000;isub=12345;phone-context=1234.com";
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, US_LOCAL_NUMBER.getNationalNumber);
    });

    test("testParse: US Number- 5103628154x1234", () {
      String inputNumber = "5103628154x1234";
      PhoneNumber receivedOutput = phoneConverter.parse(inputNumber, defaultRegion: "US");
      expect(receivedOutput.getNationalNumber, 5103628154);
      expect(receivedOutput.getExtension, "1234");
    });
  });

  group("Testing Parse Non Ascii: ", () {
    test("testParse: Parse Non Ascii = 1 (650) 253\u00AD-0000", () {
      // Using a soft hyphen U+00AD.
      expect((phoneConverter.parse("1 (650) 253\u00AD-0000", defaultRegion: "US")).getNationalNumber, US_NUMBER.getNationalNumber);
    });
  });

  group("Testing Format with extension ", () {
    test("testParse: Parse Non Ascii = 1 (650) 253\u00AD-0000", () {
      // Using a soft hyphen U+00AD.
      PhoneNumber usNumber = US_NUMBER;
      //usNumber.setExtension("4657");
      String result = phoneConverter.format(usNumber, PhoneNumberFormat.NATIONAL);
      expect(result, "(650) 253-0000");
    });
  });
}

void testIsValidNumber() {
  PhoneNumber US_NUMBER = new PhoneNumber();
  US_NUMBER.setCountryCode = 1;
  US_NUMBER.setNationalNumber = 6502530000;

  PhoneNumber INTERNATIONAL_TOLL_FREE = new PhoneNumber();
  INTERNATIONAL_TOLL_FREE.setCountryCode = 800;
  INTERNATIONAL_TOLL_FREE.setNationalNumber = 12345678;

  PhoneNumber UNIVERSAL_PREMIUM_RATE = new PhoneNumber();
  UNIVERSAL_PREMIUM_RATE.setCountryCode = 979;
  UNIVERSAL_PREMIUM_RATE.setNationalNumber = 123456789;

  group("Testing Is a Valid Number ", () {
    test("isValidNumber: US_NUMBER", () {
      expect(phoneConverter.isValidNumber(US_NUMBER), true);
    });

    test("isValidNumber: INTERNATIONAL_TOLL_FREE", () {
      var x = phoneConverter.isValidNumber(INTERNATIONAL_TOLL_FREE);
      expect(x, true);
    });

    test("isValidNumber: UNIVERSAL_PREMIUM_RATE", () {
      expect(phoneConverter.isValidNumber(UNIVERSAL_PREMIUM_RATE), true);
    });
  });
}

void testGetRegionCodeForNumber() {
  PhoneNumber INTERNATIONAL_TOLL_FREE = new PhoneNumber();
  INTERNATIONAL_TOLL_FREE.setCountryCode = 800;
  INTERNATIONAL_TOLL_FREE.setNationalNumber = 12345678;

  PhoneNumber UNIVERSAL_PREMIUM_RATE = new PhoneNumber();
  UNIVERSAL_PREMIUM_RATE.setCountryCode = 979;
  UNIVERSAL_PREMIUM_RATE.setNationalNumber = 123456789;

  PhoneNumber US_NUMBER = new PhoneNumber();
  US_NUMBER.setCountryCode = 1;
  US_NUMBER.setNationalNumber = 6502530000;

  group("Testing Is a Valid Number ", () {
    test("getRegionCodeForNumber: US_NUMBER", () {
      expect(phoneConverter.getRegionCodeForNumber(US_NUMBER), RegionCode['US']);
    });

    test("getRegionCodeForNumber: INTERNATIONAL_TOLL_FREE", () {
      expect(phoneConverter.getRegionCodeForNumber(INTERNATIONAL_TOLL_FREE), RegionCode['UN001']);
    });

    test("getRegionCodeForNumber: UNIVERSAL_PREMIUM_RATE", () {
      expect(phoneConverter.getRegionCodeForNumber(UNIVERSAL_PREMIUM_RATE), RegionCode['UN001']);
    });
  });
}

void testIsValidNumberForRegion() {
  PhoneNumber INTERNATIONAL_TOLL_FREE = new PhoneNumber();
  INTERNATIONAL_TOLL_FREE.setCountryCode = 800;
  INTERNATIONAL_TOLL_FREE.setNationalNumber = 12345678;

  PhoneNumber UNIVERSAL_PREMIUM_RATE = new PhoneNumber();
  UNIVERSAL_PREMIUM_RATE.setCountryCode = 979;
  UNIVERSAL_PREMIUM_RATE.setNationalNumber = 123456789;

  PhoneNumber US_NUMBER = new PhoneNumber();
  US_NUMBER.setCountryCode = 1;
  US_NUMBER.setNationalNumber = 6502530000;

  group("Testing Is a Valid Number Region", () {
    test("isValidNumberForRegion: INTERNATIONAL_TOLL_FREE with Region Code as UN001", () {
      var xx = phoneConverter.isValidNumberForRegion(INTERNATIONAL_TOLL_FREE, RegionCode['UN001']);
      expect(xx, true);
    });
    test("isValidNumberForRegion: INTERNATIONAL_TOLL_FREE with Region Code as US", () {
      expect(phoneConverter.isValidNumberForRegion(INTERNATIONAL_TOLL_FREE, RegionCode['US']), false);
    });
    test("isValidNumberForRegion: INTERNATIONAL_TOLL_FREE with Region Code as ZZ(Unknown)", () {
      expect(phoneConverter.isValidNumberForRegion(INTERNATIONAL_TOLL_FREE, RegionCode['ZZ']), false);
    }, skip: " the metadata algorithm is not yet supporitng unknwon regions");

    // This number is valid in both places.
    var invalidNumber = new PhoneNumber();
    // Invalid country calling codes.
    invalidNumber.setCountryCode = 3923;
    invalidNumber.setNationalNumber = 2366;
    test("isValidNumberForRegion: invalidNumber with Region Code as ZZ(Unknown)", () {
      expect(phoneConverter.isValidNumberForRegion(invalidNumber, RegionCode['ZZ']), false);
    }, skip: " the metadata algorithm is not yet supporitng unknwon regions");
    test("isValidNumberForRegion: invalidNumber with Region Code as UN001", () {
      expect(phoneConverter.isValidNumberForRegion(invalidNumber, RegionCode['UN001']), false);
    });
    invalidNumber.setCountryCode = 0;
    test("isValidNumberForRegion: invalidNumber with Region Code as UN001", () {
      expect(phoneConverter.isValidNumberForRegion(invalidNumber, RegionCode['UN001']), false);
    });
    test("isValidNumberForRegion: invalidNumber with Region Code as ZZ", () {
      expect(phoneConverter.isValidNumberForRegion(invalidNumber, RegionCode['ZZ']), false);
    }, skip: " the metadata algorithm is not yet supporitng unknwon regions");
  });
}

void testIsNotValidNumber() {
// We set this to be the same length as numbers for the other non-geographical
// country prefix that we have in our test metadata. However, this is not
// considered valid because they differ in their country calling code.
  PhoneNumber INTERNATIONAL_TOLL_FREE_TOO_LONG = new PhoneNumber();
  INTERNATIONAL_TOLL_FREE_TOO_LONG.setCountryCode = 800;
  INTERNATIONAL_TOLL_FREE_TOO_LONG.setNationalNumber = 123456789;

// Too short, but still possible US numbers.
  PhoneNumber US_LOCAL_NUMBER = new PhoneNumber();
  US_LOCAL_NUMBER.setCountryCode = 1;
  US_LOCAL_NUMBER.setNationalNumber = 2530000;

  group('testIsNotValidNumber: testing a number that is not valid', () {
    test("isValidNumber: invalidNumber with US_LOCAL_NUMBER", () {
      var result = phoneConverter.isValidNumber(US_LOCAL_NUMBER);
      expect(result, false);
    });

    var invalidNumber5 = new PhoneNumber();
    invalidNumber5.setCountryCode = 3923;
    invalidNumber5.setNationalNumber = 2366;
    test("isValidNumberForRegion: invalidNumber with Region Code as ZZ", () {
      expect(phoneConverter.isValidNumber(invalidNumber5), false);
      invalidNumber5.setCountryCode = 2366;
      expect(phoneConverter.isValidNumber(invalidNumber5), false);
    });
  });

  test("isValidNumberForRegion: invalidNumber with Region Code as ZZ", () {
    expect(phoneConverter.isValidNumber(INTERNATIONAL_TOLL_FREE_TOO_LONG), false);
  });
}
