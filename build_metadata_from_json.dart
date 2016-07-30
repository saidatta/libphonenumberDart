library building_json;

import 'package:ascentis_io/ascentis_io.dart';
import 'package:dart_util/dart_util.dart';
import 'dart:convert';
import 'dart:async';
import "package:ascentis_logger/ascentis_logger.dart";

class BuildMetaDataFromJSON {
  AscentisLogger _logger = new AscentisLogger("BuildMetaDataFromJSON");

  static const CARRIER_CODE_FORMATTING_RULE = "@carrierCodeFormattingRule";
  static const CARRIER_SPECIFIC = "carrierSpecific";
  static const COUNTRY_CODE = "countryCode";
  static const EMERGENCY = "emergency";
  static const EXAMPLE_NUMBER = "exampleNumber";
  static const FIXED_LINE = "fixedLine";
  static const FORMAT = "format";
  static const GENERAL_DESC = "generalDesc";
  static const INTERNATIONAL_PREFIX = "internationalPrefix";
  static const INTL_FORMAT = "intlFormat";
  static const LEADING_DIGITS = "leadingDigits";
  static const LEADING_ZERO_POSSIBLE = "leadingZeroPossible";
  static const MAIN_COUNTRY_FOR_CODE = "mainCountryForCode";
  static const AVAILABLE_FORMATS = "availableFormats";
  static const MOBILE = "mobile";
  static const MOBILE_NUMBER_PORTABLE_REGION = "mobileNumberPortableRegion";
  static const NATIONAL_NUMBER_PATTERN = "nationalNumberPattern";
  static const NATIONAL_PREFIX = "nationalPrefix";
  static const NATIONAL_PREFIX_FORMATTING_RULE = "@nationalPrefixFormattingRule";
  static const NATIONAL_PREFIX_OPTIONAL_WHEN_FORMATTING = "@nationalPrefixOptionalWhenFormatting";
  static const NATIONAL_PREFIX_FOR_PARSING = "nationalPrefixForParsing";
  static const NATIONAL_PREFIX_TRANSFORM_RULE = "nationalPrefixTransformRule";
  static const NO_INTERNATIONAL_DIALLING = "noInternationalDialling";
  static const NUMBER_FORMAT = "numberFormat";
  static const PAGER = "pager";
  static const PATTERN = "pattern";
  static const PERSONAL_NUMBER = "personalNumber";
  static const POSSIBLE_NUMBER_PATTERN = "possibleNumberPattern";
  static const PREFERRED_EXTN_PREFIX = "preferredExtnPrefix";
  static const PREFERRED_INTERNATIONAL_PREFIX = "preferredInternationalPrefix";
  static const PREMIUM_RATE = "premiumRate";
  static const SHARED_COST = "sharedCost";
  static const SHORT_CODE = "shortCode";
  static const STANDARD_RATE = "standardRate";
  static const TOLL_FREE = "tollFree";
  static const UAN = "uan";
  static const VOICEMAIL = "voicemail";
  static const VOIP = "voip";
  static const VALUE = "\$t";
  static const UNKNOWN = "0";

  Map decodedMetaData;

  StreamController _fileStream = new StreamController();
  Stream get onFileLoaded => _fileStream.stream;

  BuildMetaDataFromJSON() {}

  Future loadMetaData(String path) async {
    RestIO restIO = new RestIO();
    var result = await restIO.read(path);
    _logger.fine('Has successfully read the file from $path');
    var decodedResult = JSON.decode(result);
    this.decodedMetaData = decodedResult;
  }

  PhoneMetadata getRegionData(String regionCode) {
    return _constructRegionData(regionCode);
  }

  /**
   * This method will construct Region data from the JSON read map based on the RegionCode.
   */
  PhoneMetadata _constructRegionData(String regionCode) {
    _logger.fine('constructRegionData -  $regionCode');
    List allTerritories = this.decodedMetaData["phoneNumberMetadata"]["territories"]["territory"];
    for (Map currentTerritory in allTerritories) {
      // id == regionCode for all counties
      // coutnryCode == regionCode for Toll free numbers.
      //TODO: unknown regions detection.
      if (currentTerritory["id"] == regionCode || currentTerritory['countryCode'] == regionCode) {
        _logger.fine('found territory with following regionCode: $regionCode');
        return loadCountryMetadata(regionCode, currentTerritory, false, false, false);
      }
    }
    return null;
  }

  /**
   * This method will translate the specific country Metadata from JSON to a Dart Object.
   */
  PhoneMetadata loadCountryMetadata(
      String regionCode, Map element, bool liteBuild, bool isShortNumberMetadata, bool isAlternateFormatsMetadata) {
    String nationalPrefix = getNationalPrefix(element);
    PhoneMetadata metadata = loadTerritoryTagMetadata(regionCode, element, nationalPrefix);
    String nationalPrefixFormattingRule = getNationalPrefixFormattingRuleFromElement(element, nationalPrefix);
    loadAvailableFormats(
        metadata, element, nationalPrefix, nationalPrefixFormattingRule, element.containsKey(NATIONAL_PREFIX_OPTIONAL_WHEN_FORMATTING));
    if (!isAlternateFormatsMetadata) {
      //TODO: When adding more phone descriptsion.
      // The alternate formats metadata does not need most of the patterns to be set.
      setRelevantDescPatterns(metadata, element, liteBuild, isShortNumberMetadata);
    }
    return metadata;
  }

  bool isValidNumberType(String numberType) {
    return numberType == (FIXED_LINE) || numberType == (MOBILE) || numberType == (GENERAL_DESC);
  }

  /**
   * Processes a phone number description element from the JSON file and returns it as a
   * PhoneNumberDesc. If the description element is a fixed line or mobile number, the general
   * description will be used to fill in the whole element if necessary, or any components that are
   * missing. For all other types, the general description will only be used to fill in missing
   * components if the type has a partial definition. For example, if no "tollFree" element exists,
   * we assume there are no toll free numbers for that locale, and return a phone number description
   * with "NA" for both the national and possible number patterns.
   *
   * @param generalDesc  a generic phone number description that will be used to fill in missing
   *                     parts of the description
   * @param countryElement  the JSON element representing all the country information
   * @param numberType  the name of the number type, corresponding to the appropriate tag in the JSON
   *                    file with information about that type
   * @return  complete description of that phone number type
   */
  PhoneNumberDesc processPhoneNumberDescElement(PhoneNumberDesc generalDesc, Map countryElement, String numberType, bool liteBuild) {
    var phoneNumberDesMap = getObject(numberType, countryElement);
    PhoneNumberDesc numberDesc = new PhoneNumberDesc();
    if ((phoneNumberDesMap == null || phoneNumberDesMap.length == 0) && !isValidNumberType(numberType)) {
      numberDesc.nationalNumberPattern = "NA";
      numberDesc.possibleNumberPattern = "NA";
      return numberDesc;
    }
    // TODO: Refactor into a utility class.
    if (!isNullOrEmpty(generalDesc.nationalNumberPattern)) {
      numberDesc.nationalNumberPattern = generalDesc.nationalNumberPattern;
    }
    if (!isNullOrEmpty(generalDesc.possibleNumberPattern)) {
      numberDesc.possibleNumberPattern = generalDesc.possibleNumberPattern;
    }
    if (!isNullOrEmpty(generalDesc.exampleNumber)) {
      numberDesc.exampleNumber = generalDesc.exampleNumber;
    }

    if (phoneNumberDesMap != null && phoneNumberDesMap.isNotEmpty) {
      Map element = phoneNumberDesMap;
      //Getting the possiblenumberpattern: {$ : regex}
      Map possiblePattern = element[POSSIBLE_NUMBER_PATTERN];
      if (possiblePattern != null && possiblePattern.isNotEmpty) {
        String temp = possiblePattern["\$"];
        if (temp == null) {
          temp = possiblePattern["\$t"];
        }
        numberDesc.possibleNumberPattern = validateRegex(temp, true);
      }

      Map validPattern = element[NATIONAL_NUMBER_PATTERN];
      if (validPattern != null && validPattern.isNotEmpty) {
        String temp = validPattern["\$"];
        if (temp == null) {
          temp = validPattern["\$t"];
        }
        numberDesc.nationalNumberPattern = validateRegex(temp, true);
      }

      if (!liteBuild) {
        Map exampleNumber = element[EXAMPLE_NUMBER];
        if (exampleNumber != null && exampleNumber.isNotEmpty) {
          String temp = exampleNumber["\$"];
          if (temp == null) {
            temp = exampleNumber["\$t"];
          }
          numberDesc.exampleNumber = temp;
        }
      }
    }
    return numberDesc;
  }

  void setRelevantDescPatterns(PhoneMetadata metadata, Map element, bool liteBuild, bool isShortNumberMetadata) {
    PhoneNumberDesc generalDesc = new PhoneNumberDesc();
    generalDesc = processPhoneNumberDescElement(generalDesc, element, GENERAL_DESC, liteBuild);
    metadata.generalDesc = generalDesc;

    if (!isShortNumberMetadata) {
      // Set fields used only by regular length phone numbers.
      metadata.fixedLine = processPhoneNumberDescElement(generalDesc, element, FIXED_LINE, liteBuild);
      metadata.mobile = processPhoneNumberDescElement(generalDesc, element, MOBILE, liteBuild);
      metadata.sharedCost = processPhoneNumberDescElement(generalDesc, element, SHARED_COST, liteBuild);
      metadata.voip = processPhoneNumberDescElement(generalDesc, element, VOIP, liteBuild);
      metadata.personalNumber = processPhoneNumberDescElement(generalDesc, element, PERSONAL_NUMBER, liteBuild);
      metadata.pager = processPhoneNumberDescElement(generalDesc, element, PAGER, liteBuild);
      metadata.uan = processPhoneNumberDescElement(generalDesc, element, UAN, liteBuild);
      metadata.voicemail = processPhoneNumberDescElement(generalDesc, element, VOICEMAIL, liteBuild);
      metadata.noInternationalDialling = processPhoneNumberDescElement(generalDesc, element, NO_INTERNATIONAL_DIALLING, liteBuild);
      metadata.sameMobileAndFixedLinePattern = metadata.mobile.nationalNumberPattern == (metadata.fixedLine.nationalNumberPattern);
    } else {
      // Set fields used only by short numbers.
      metadata.standardRate = processPhoneNumberDescElement(generalDesc, element, STANDARD_RATE, liteBuild);
      metadata.shortCode = processPhoneNumberDescElement(generalDesc, element, SHORT_CODE, liteBuild);
      metadata.carrierSpecific = processPhoneNumberDescElement(generalDesc, element, CARRIER_SPECIFIC, liteBuild);
      metadata.emergency = processPhoneNumberDescElement(generalDesc, element, EMERGENCY, liteBuild);
    }

    // Set fields used by both regular length and short numbers.
    metadata.tollFree = processPhoneNumberDescElement(generalDesc, element, TOLL_FREE, liteBuild);
    metadata.premiumRate = processPhoneNumberDescElement(generalDesc, element, PREMIUM_RATE, liteBuild);
  }

  /**
   * Returns the national prefix of the provided country element.
   */
  String getNationalPrefix(Map element) {
    return element.containsKey(NATIONAL_PREFIX) ? element[NATIONAL_PREFIX] : "";
  }

  /**
   *  Extracts the available formats from the provided DOM element. If it does not contain any
   *  nationalPrefixFormattingRule, the one passed-in is retained. The nationalPrefix,
   *  nationalPrefixFormattingRule and nationalPrefixOptionalWhenFormatting values are provided from
   *  the parent (territory) element.
   */
  void loadAvailableFormats(PhoneMetadata metadata, Map element, String nationalPrefix, String nationalPrefixFormattingRule,
      bool nationalPrefixOptionalWhenFormatting) {
    String carrierCodeFormattingRule = "";
    if (element.containsKey(CARRIER_CODE_FORMATTING_RULE)) {
      carrierCodeFormattingRule = _validateRE(getDomesticCarrierCodeFormattingRuleFromElement(element, nationalPrefix));
    }
    Map availableFormatElements = element["availableFormats"];

    if (availableFormatElements != null) {
      var numberFormatElements = availableFormatElements[NUMBER_FORMAT];
      bool hasExplicitIntlFormatDefined = false;

      int numOfFormatElements = numberFormatElements.length;
      for (int i = 0; i < numOfFormatElements; i++) {
        // if length is 1 then it is received as a Map instead of List of Maps
        Map numberFormatElement = (numberFormatElements is Map) ? numberFormatElements : numberFormatElements[i];
        NumberFormat format = new NumberFormat();

        if (numberFormatElement.containsKey(NATIONAL_PREFIX_FORMATTING_RULE)) {
          format.nationalPrefixFormattingRule = getNationalPrefixFormattingRuleFromElement(numberFormatElement, nationalPrefix);
        } else {
          format.nationalPrefixFormattingRule = nationalPrefixFormattingRule;
        }

        if (numberFormatElement.containsKey(NATIONAL_PREFIX_OPTIONAL_WHEN_FORMATTING)) {
          format.nationalPrefixOptionalWhenFormatting = (numberFormatElement[NATIONAL_PREFIX_OPTIONAL_WHEN_FORMATTING]) == null
              ? false
              : numberFormatElement[NATIONAL_PREFIX_OPTIONAL_WHEN_FORMATTING].toLowerCase() == 'true';
        } else {
          format.nationalPrefixOptionalWhenFormatting = nationalPrefixOptionalWhenFormatting;
        }
        if (numberFormatElement.containsKey(CARRIER_CODE_FORMATTING_RULE)) {
          format.domesticCarrierCodeFormattingRule =
              _validateRE(getDomesticCarrierCodeFormattingRuleFromElement(numberFormatElement, nationalPrefix));
        } else {
          format.domesticCarrierCodeFormattingRule = carrierCodeFormattingRule;
        }
        loadNationalFormat(metadata, numberFormatElement, format);
        List<NumberFormat> formatList = (metadata.numberFormat == null) ? new List() : new List<NumberFormat>.from(metadata.numberFormat);
        formatList.add(format);
        metadata.numberFormat = formatList;

        if (loadInternationalFormat(metadata, numberFormatElement, format)) {
          hasExplicitIntlFormatDefined = true;
        }
      }
      // Only a small number of regions need to specify the intlFormats in the json. For the majority
      // of countries the intlNumberFormat metadata is an exact copy of the national NumberFormat
      // metadata. To minimize the size of the metadata file, we only keep intlNumberFormats that
      // actually differ in some way to the national formats.
      if (!hasExplicitIntlFormatDefined) {
        metadata.intlNumberFormat = new List<NumberFormat>();
      }
    }
  }

  String getNationalPrefixFormattingRuleFromElement(Map element, String nationalPrefix) {
    String nationalPrefixFormattingRule = element[NATIONAL_PREFIX_FORMATTING_RULE];
    if (nationalPrefixFormattingRule == null) {
      return null;
    }
    // Replace $NP with national prefix and $FG with the first group ($1).
    nationalPrefixFormattingRule = nationalPrefixFormattingRule.replaceFirst("\$NP", nationalPrefix).replaceFirst("\$FG", "\${m[1]}");
    return nationalPrefixFormattingRule;
  }

  String getDomesticCarrierCodeFormattingRuleFromElement(Map element, String nationalPrefix) {
    String carrierCodeFormattingRule = element[CARRIER_CODE_FORMATTING_RULE];
    // Replace $FG with the first group ($1) and $NP with the national prefix.
    carrierCodeFormattingRule = carrierCodeFormattingRule.replaceFirst("\$FG", "\${m[1]}").replaceFirst("\$NP", nationalPrefix);
    return carrierCodeFormattingRule;
  }

  /**
   * Extracts the pattern for the national format.
   *
   * @throws  RuntimeException if multiple or no formats have been encountered.
   */
  void loadNationalFormat(PhoneMetadata metadata, Map numberFormatElement, NumberFormat format) {
    setLeadingDigitsPatterns(numberFormatElement, format);
    format.pattern = _validateRE(numberFormatElement[PATTERN]);

    String formatPattern = numberFormatElement[FORMAT][VALUE];
    //if nationalformat is a list with more than 1 then it is invalid.
    format.format = formatPattern;
  }

  PhoneMetadata loadTerritoryTagMetadata(String regionCode, Map jsonMap, String nationalPrefix) {
    PhoneMetadata metadata = new PhoneMetadata();
    metadata.id = regionCode;
    if (jsonMap.containsKey(COUNTRY_CODE)) {
      metadata.countryCode = int.parse(jsonMap[COUNTRY_CODE]);
    }
    if (jsonMap.containsKey(LEADING_DIGITS)) {
      metadata.leadingDigits = _validateRE(jsonMap[LEADING_DIGITS]);
    }
    metadata.internationalPrefix = _validateRE(jsonMap[INTERNATIONAL_PREFIX]);
    if (jsonMap.containsKey(PREFERRED_INTERNATIONAL_PREFIX)) {
      metadata.preferredInternationalPrefix = jsonMap[PREFERRED_INTERNATIONAL_PREFIX];
    }
    if (jsonMap.containsKey(NATIONAL_PREFIX_FOR_PARSING)) {
      metadata.nationalPrefixForParsing = validateRegex(jsonMap[NATIONAL_PREFIX_FOR_PARSING], true);
      if (jsonMap.containsKey(NATIONAL_PREFIX_TRANSFORM_RULE)) {
        metadata.nationalPrefixTransformRule = _validateRE(jsonMap[NATIONAL_PREFIX_TRANSFORM_RULE]);
      }
    }
    if (!nationalPrefix.isEmpty) {
      metadata.nationalPrefix = nationalPrefix;
      if (metadata.nationalPrefixForParsing == "") {
        metadata.nationalPrefixForParsing = nationalPrefix;
      }
    }
    if (jsonMap.containsKey(PREFERRED_EXTN_PREFIX)) {
      metadata.preferredExtnPrefix = jsonMap[PREFERRED_EXTN_PREFIX];
    }
    if (jsonMap.containsKey(MAIN_COUNTRY_FOR_CODE)) {
      metadata.mainCountryForCode = true;
    }
    if (jsonMap.containsKey(LEADING_ZERO_POSSIBLE)) {
      metadata.leadingZeroPossible = true;
    }
    if (jsonMap.containsKey(MOBILE_NUMBER_PORTABLE_REGION)) {
      metadata.mobileNumberPortableRegion = true;
    }
    return metadata;
  }

  /**
   * Extracts the pattern for international format. If there is no intlFormat, default to using the
   * national format. If the intlFormat is set to "NA" the intlFormat should be ignored.
   *
   * @throws  RuntimeException if multiple intlFormats have been encountered.
   * @return  whether an international number format is defined.
   */
  bool loadInternationalFormat(PhoneMetadata metadata, Map numberFormat, NumberFormat nationalFormat) {
    NumberFormat intlFormat = new NumberFormat();
    bool hasExplicitIntlFormatDefined = false;
    if (numberFormat[INTL_FORMAT] == null) {
      intlFormat = (nationalFormat);
      return false;
    }
    String intlFormatPattern = numberFormat[INTL_FORMAT][VALUE];

    //TODO: if pattern is a list and has more than 1 then throw an exception.
    if (intlFormatPattern == null) {
      // Default to use the same as the national pattern if none is defined.
      intlFormat = (nationalFormat);
    } else {
      intlFormat.pattern = numberFormat[PATTERN];
      setLeadingDigitsPatterns(numberFormat, intlFormat);
      String intlFormatPatternValue = intlFormatPattern;
      if (intlFormatPatternValue != "NA") {
        intlFormat.format = intlFormatPatternValue;
      }
      hasExplicitIntlFormatDefined = true;
    }

    if (intlFormat.format != "") {
      List<NumberFormat> formatList =
          (metadata.intlNumberFormat == null) ? new List() : new List<NumberFormat>.from(metadata.intlNumberFormat);
      formatList.add(intlFormat);
      metadata.intlNumberFormat = formatList;
    }
    return hasExplicitIntlFormatDefined;
  }

  void setLeadingDigitsPatterns(Map numberFormatElement, NumberFormat format) {
    var leadingDigitsPatternNodes = numberFormatElement[LEADING_DIGITS];
    List lDigitPatternList = new List();
    if (leadingDigitsPatternNodes == null) {
      return;
    }
    if (leadingDigitsPatternNodes is List) {
      lDigitPatternList.addAll(leadingDigitsPatternNodes);
    } else {
      lDigitPatternList.add(leadingDigitsPatternNodes);
    }

    int numOfLeadingDigitsPatterns = lDigitPatternList.length;
    if (numOfLeadingDigitsPatterns > 0) {
      List<String> patternList = new List.from(format.leadingDigitsPattern);
      for (int i = 0; i < numOfLeadingDigitsPatterns; i++) {
        patternList.add(validateRegex(lDigitPatternList[i]["\$t"], true));
      }
      format.leadingDigitsPattern = patternList;
    }
  }

  String validateRegex(String regex, bool removeWhitespace) {
    // Removes all the whitespace and newline from the regexp. Not using pattern compile options to
    // make it work across programming languages.
    if (regex == null) {
      return null;
    }
    String compressedRegex = removeWhitespace ? regex.replaceAll(new RegExp(r"\s"), "") : regex;
    // We don't ever expect to see | followed by a ) in our metadata - this would be an indication
    // of a bug. If one wants to make something optional, we prefer ? to using an empty group.
    int errorIndex = compressedRegex.indexOf("|)");
    if (errorIndex >= 0) {
      /// Pattern syntax exception
      return null;
    }
    // return the regex if it is of correct syntax, i.e. compile did not fail with a
    // PatternSyntaxException.
    return compressedRegex;
  }

  String _validateRE(String regex) => validateRegex(regex, false);

  /**
   * This is a helper method for traversing through a nested Map to find the appropriate value based on the requested Key.
   */
  dynamic getObject(String requestKey, Map elementMap) {
    if (elementMap[requestKey] != null) {
      return elementMap[requestKey];
    }

    for (String key in elementMap.keys) {
      if (elementMap[key] is Map) {
        return getObject(requestKey, elementMap[key]);
      }
    }
    return null;
  }
}

class PhoneMetadata {
  // These variables correspond to the attributes within the related phone meta data json.
  String id = '';
  int countryCode = 0;
  String leadingDigits = '';
  String internationalPrefix = '';
  String preferredInternationalPrefix = '';
  String nationalPrefixForParsing = '';
  String nationalPrefixTransformRule = '';
  String nationalPrefix = '';
  String preferredExtnPrefix = '';

  PhoneNumberDesc generalDesc;
  PhoneNumberDesc fixedLine;
  PhoneNumberDesc premiumRate;
  PhoneNumberDesc standardRate;
  PhoneNumberDesc shortCode;
  PhoneNumberDesc carrierSpecific;
  PhoneNumberDesc tollFree;
  PhoneNumberDesc mobile;
  PhoneNumberDesc sharedCost;
  PhoneNumberDesc voip;
  PhoneNumberDesc personalNumber;
  PhoneNumberDesc pager;
  PhoneNumberDesc uan;
  PhoneNumberDesc voicemail;
  PhoneNumberDesc noInternationalDialling;
  PhoneNumberDesc emergency;

  bool sameMobileAndFixedLinePattern = false;
  bool mobileNumberPortableRegion = false;
  bool leadingZeroPossible = false;
  bool mainCountryForCode = false;
  List<NumberFormat> numberFormat;
  List<NumberFormat> intlNumberFormat;
  List<String> leadingDigitsPattern;

  bool hasNationalPrefix() {
    return this.nationalPrefix != null && this.nationalPrefix != '';
  }

  bool hasLeadingDigits() {
    return this.leadingDigits != null && this.leadingDigits != '';
  }

  bool hasPreferredInternationalPrefix() {
    return this.preferredInternationalPrefix != null && this.preferredInternationalPrefix != '';
  }

  String getPreferredInternationalPrefixOrDefault() {
    return this.preferredInternationalPrefix ?? '';
  }

  int getCountryCodeOrDefault() {
    return this.countryCode ?? 0;
  }

  String getNationalPrefixOrDefault() {
    return this.nationalPrefix ?? '';
  }
}

class PhoneNumberDesc {
  String nationalNumberPattern = '';
  String possibleNumberPattern = '';
  String exampleNumber = '';
}

/**
 * This class is meant to keep track of all data respect to NumberFormat.
 */
class NumberFormat {
  String pattern;
  String format;
  List<String> leadingDigitsPattern;
  String nationalPrefixFormattingRule;
  bool nationalPrefixOptionalWhenFormatting;
  String domesticCarrierCodeFormattingRule;

  NumberFormat() {
    clear();
  }

  void clear() {
    pattern = "";
    format = "";
    leadingDigitsPattern = new List<String>();
    nationalPrefixFormattingRule = "";
    nationalPrefixOptionalWhenFormatting = false;
    domesticCarrierCodeFormattingRule = "";
  }
}
