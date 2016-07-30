import 'dart:collection';
import "package:ascentis_logger/ascentis_logger.dart";
import 'build_metadata_from_json.dart';
import 'package:dart_util/dart_util.dart';
import '../default_data.dart';
import 'phone_number.dart';
import 'dart:async';

/**
 * INTERNATIONAL and NATIONAL formats are consistent with the definition in ITU-T Recommendation
 * E123. For example, the number of the Google Switzerland office will be written as
 * "+41 44 668 1800" in INTERNATIONAL format, and as "044 668 1800" in NATIONAL format.
 * E164 format is as per INTERNATIONAL format but with no formatting applied, e.g.
 * "+41446681800". RFC3966 is as per INTERNATIONAL format, but with all spaces and other
 * separating symbols replaced with a hyphen, and with any phone number extension appended with
 * ";ext=". It also will have a prefix of "tel:" added, e.g. "tel:+41-44-668-1800".
 *
 * Note: If you are considering storing the number in a neutral format, you are highly advised to
 * use the PhoneNumber class.
 */
enum PhoneNumberFormat { E164, INTERNATIONAL, NATIONAL, RFC3966 }

/**
 * Possible outcomes when testing if a PhoneNumber is possible.
 *
 * @enum {number}
 */
enum ValidationResult { IS_POSSIBLE, INVALID_COUNTRY_CODE, TOO_SHORT, TOO_LONG }

/**
 * Type of phone numbers.
 *
 * @enum {number}
 */
enum PhoneNumberType {
  FIXED_LINE,
  MOBILE,
// In some regions (e.g. the USA), it is impossible to distinguish between
// fixed-line and mobile numbers by looking at the phone number itself.
  FIXED_LINE_OR_MOBILE,
// Freephone lines
  TOLL_FREE,
  PREMIUM_RATE,
// The cost of this call is shared between the caller and the recipient, and
// is hence typically less than PREMIUM_RATE calls. See
// http://en.wikipedia.org/wiki/Shared_Cost_Service for more information.
  SHARED_COST,
// Voice over IP numbers. This includes TSoIP (Telephony Service over IP).
  VOIP,
// A personal number is associated with a particular person, and may be routed
// to either a MOBILE or FIXED_LINE number. Some more information can be found
// here: http://en.wikipedia.org/wiki/Personal_Numbers
  PERSONAL_NUMBER,
  PAGER,
// Used for 'Universal Access Numbers' or 'Company Numbers'. They may be
// further routed to specific offices, but allow one number to be used for a
// company.
  UAN,
// Used for 'Voice Mail Access Numbers'.
  VOICEMAIL,
// A phone number is of type UNKNOWN when it does not fit any of the known
// patterns for a specific region.
  UNKNOWN
}

/**
 * Errors encountered when parsing phone numbers.
 *
 * @enum {string}
 */
enum ErrorType {
  INVALID_COUNTRY_CODE, //('Invalid country calling code'),
// This generally indicates the string passed in had less than 3 digits in it.
// More specifically, the number failed to match the regular expression
// VALID_PHONE_NUMBER.
  NOT_A_NUMBER, // ('The string supplied did not seem to be a phone number');
// This indicates the string started with an international dialing prefix, but
// after this was stripped from the number, had less digits than any valid
// phone number (including country calling code) could have.
  TOO_SHORT_AFTER_IDD, //'Phone number too short after IDD'),
// This indicates the string, after any country calling code has been
// stripped, had less digits than any valid phone number could have.
  TOO_SHORT_NSN, //('The string supplied is too short to be a phone number'),
// This indicates the string had more digits than any valid phone number could
// have.
  TOO_LONG //('The string supplied is too long to be a phone number')
}

class PhoneConverter {
  AscentisLogger logger = new AscentisLogger("PhoneConverter");

  BuildMetaDataFromJSON metaDataFromJSON;

  /**
   * The maximum length of the country calling code.
   *
   * @const
   * @type {number}
   * @private
   */
  static const _MAX_LENGTH_COUNTRY_CODE = 3;

  // We don't allow input strings for parsing to be longer than 250 chars. This prevents malicious
  // input from overflowing the regular-expression engine.
  static const _MAX_INPUT_STRING_LENGTH = 250;

  // The minimum and maximum length of the national significant number.
  static const _MIN_LENGTH_FOR_NSN = 2;
  /**
   * The ITU says the maximum length should be 15, but we have found longer
   * numbers in Germany.
   *
   * @const
   * @type {number}
   * @private
   */
  static const _MAX_LENGTH_FOR_NSN = 17;

  static const _STAR_SIGN = '*';
  /**
   * Region-code for the unknown region.
   *
   * @const
   * @type {string}
   * @private
   */
  static const _UNKNOWN_REGION = 'ZZ';

  // The set of regions the library supports.
  // There are roughly 240 of them and we set the initial capacity of the HashSet to 320 to offer a
  // load factor of roughly 0.75.
  static final Set<String> supportedRegions = new HashSet<String>();

  static const _CC_PATTERN = r'/\$CC/';
  /**
   * This was originally set to $1 but there are some countries for which the
   * first group is not used in the national pattern (e.g. Argentina) so the $1
   * group does not match correctly.  Therefore, we use \d, so that the first
   * group actually used in the pattern will be matched.
   * @constf
   * @type {!RegExp}
   * @private
   */
  static final _FIRST_GROUP_PATTERN = new RegExp(r'(\$\d)');

  /**
   * Pattern that makes it easy to distinguish whether a region has a unique
   * international dialing prefix or not. If a region has a unique international
   * prefix (e.g. 011 in USA), it will be represented as a string that contains a
   * sequence of ASCII digits. If there are multiple available international
   * prefixes in a region, they will be represented as a regex string that always
   * contains character(s) other than ASCII digits. Note this regex also includes
   * tilde, which signals waiting for the tone.
   *
   * @const
   * @type {!RegExp}
   * @private
   */
  static final _UNIQUE_INTERNATIONAL_PREFIX = new RegExp(r'[\d]+(?:[~\u2053\u223C\uFF5E][\d]+)?/');

  /**
   * A mapping from a region code to the PhoneMetadata for that region.
   * @type {Object.<string, i18n.phonenumbers.PhoneMetadata>}
   */
  Map regionToMetadataMap = {};

  /**
   * For performance reasons, amalgamate both into one map.
   *
   * @const
   * @type {!Object.<string, string>}
   * @private
   */
  static final Map<String, String> _ALL_NORMALIZATION_MAPPINGS = {
    '0': '0',
    '1': '1',
    '2': '2',
    '3': '3',
    '4': '4',
    '5': '5',
    '6': '6',
    '7': '7',
    '8': '8',
    '9': '9',
    '\uFF10': '0', // Fullwidth digit 0
    '\uFF11': '1', // Fullwidth digit 1
    '\uFF12': '2', // Fullwidth digit 2
    '\uFF13': '3', // Fullwidth digit 3
    '\uFF14': '4', // Fullwidth digit 4
    '\uFF15': '5', // Fullwidth digit 5
    '\uFF16': '6', // Fullwidth digit 6
    '\uFF17': '7', // Fullwidth digit 7
    '\uFF18': '8', // Fullwidth digit 8
    '\uFF19': '9', // Fullwidth digit 9
    '\u0660': '0', // Arabic-indic digit 0
    '\u0661': '1', // Arabic-indic digit 1
    '\u0662': '2', // Arabic-indic digit 2
    '\u0663': '3', // Arabic-indic digit 3
    '\u0664': '4', // Arabic-indic digit 4
    '\u0665': '5', // Arabic-indic digit 5
    '\u0666': '6', // Arabic-indic digit 6
    '\u0667': '7', // Arabic-indic digit 7
    '\u0668': '8', // Arabic-indic digit 8
    '\u0669': '9', // Arabic-indic digit 9
    '\u06F0': '0', // Eastern-Arabic digit 0
    '\u06F1': '1', // Eastern-Arabic digit 1
    '\u06F2': '2', // Eastern-Arabic digit 2
    '\u06F3': '3', // Eastern-Arabic digit 3
    '\u06F4': '4', // Eastern-Arabic digit 4
    '\u06F5': '5', // Eastern-Arabic digit 5
    '\u06F6': '6', // Eastern-Arabic digit 6
    '\u06F7': '7', // Eastern-Arabic digit 7
    '\u06F8': '8', // Eastern-Arabic digit 8
    '\u06F9': '9', // Eastern-Arabic digit 9
    'A': '2',
    'B': '2',
    'C': '2',
    'D': '3',
    'E': '3',
    'F': '3',
    'G': '4',
    'H': '4',
    'I': '4',
    'J': '5',
    'K': '5',
    'L': '5',
    'M': '6',
    'N': '6',
    'O': '6',
    'P': '7',
    'Q': '7',
    'R': '7',
    'S': '7',
    'T': '8',
    'U': '8',
    'V': '8',
    'W': '9',
    'X': '9',
    'Y': '9',
    'Z': '9'
  };

  /**
   * These mappings map a character (key) to a specific digit that should replace
   * it for normalization purposes. Non-European digits that may be used in phone
   * numbers are mapped to a European equivalent.
   *
   * @const
   * @type {!Object.<string, string>}
   */
  static final Map<String, String> DIGIT_MAPPINGS = {
    '0': '0',
    '1': '1',
    '2': '2',
    '3': '3',
    '4': '4',
    '5': '5',
    '6': '6',
    '7': '7',
    '8': '8',
    '9': '9',
    '\uFF10': '0', // Fullwidth digit 0
    '\uFF11': '1', // Fullwidth digit 1
    '\uFF12': '2', // Fullwidth digit 2
    '\uFF13': '3', // Fullwidth digit 3
    '\uFF14': '4', // Fullwidth digit 4
    '\uFF15': '5', // Fullwidth digit 5
    '\uFF16': '6', // Fullwidth digit 6
    '\uFF17': '7', // Fullwidth digit 7
    '\uFF18': '8', // Fullwidth digit 8
    '\uFF19': '9', // Fullwidth digit 9
    '\u0660': '0', // Arabic-indic digit 0
    '\u0661': '1', // Arabic-indic digit 1
    '\u0662': '2', // Arabic-indic digit 2
    '\u0663': '3', // Arabic-indic digit 3
    '\u0664': '4', // Arabic-indic digit 4
    '\u0665': '5', // Arabic-indic digit 5
    '\u0666': '6', // Arabic-indic digit 6
    '\u0667': '7', // Arabic-indic digit 7
    '\u0668': '8', // Arabic-indic digit 8
    '\u0669': '9', // Arabic-indic digit 9
    '\u06F0': '0', // Eastern-Arabic digit 0
    '\u06F1': '1', // Eastern-Arabic digit 1
    '\u06F2': '2', // Eastern-Arabic digit 2
    '\u06F3': '3', // Eastern-Arabic digit 3
    '\u06F4': '4', // Eastern-Arabic digit 4
    '\u06F5': '5', // Eastern-Arabic digit 5
    '\u06F6': '6', // Eastern-Arabic digit 6
    '\u06F7': '7', // Eastern-Arabic digit 7
    '\u06F8': '8', // Eastern-Arabic digit 8
    '\u06F9': '9' // Eastern-Arabic digit 9
  };

  /**
   * @const
   * @type {number}
   * @private
   */
  static const _NANPA_COUNTRY_CODE = 1;

  // We accept alpha characters in phone numbers, ASCII only, upper and lower case.
  static const _VALID_ALPHA = 'A-Za-z';

  // Regular expression of acceptable punctuation found in phone numbers. This excludes punctuation
  // found as a leading character only.
  // This consists of dash characters, white space characters, full stops, slashes,
  // square brackets, parentheses and tildes. It also includes the letter 'x' as that is found as a
  // placeholder for carrier information in some phone numbers. Full-width variants are also
  // present.
  static const VALID_PUNCTUATION =
      "-x\u2010-\u2015\u2212\u30FC\uFF0D-\uFF0F " + "\u00A0\u00AD\u200B\u2060\u3000()\uFF08\uFF09\uFF3B\uFF3D.\\[\\]\\/~\u2053\u223C\uFF5E";

  // The ITU says the maximum length should be 15, but we have found longer numbers in Germany.
  static const MAX_LENGTH_FOR_NSN = 17;

  // The maximum length of the country calling code.
  static const MAX_LENGTH_COUNTRY_CODE = 3;
  static const _PLUS_CHARS = "+\uFF0B";

  /**
   * Regexp of all known extension prefixes used by different regions followed by
   * 1 or more valid digits, for use when parsing.
   *
   * @const
   * @type {!RegExp}
   * @private
   */
  RegExp _EXTN_PATTERN;

  String _SEPARATOR_PATTERN;

  /**
   * Regexp of all possible ways to write extensions, for use when parsing. This
   * will be run as a case-insensitive regexp match. Wide character versions are
   * also provided after each ASCII version. There are three regular expressions
   * here. The first covers RFC 3966 format, where the extension is added using
   * ';ext='. The second more generic one starts with optional white space and
   * ends with an optional full stop (.), followed by zero or more spaces/tabs and
   * then the numbers themselves. The other one covers the special case of
   * American numbers where the extension is written with a hash at the end, such
   * as '- 503#'. Note that the only capturing groups should be around the digits
   * that you want to capture as part of the extension, or else parsing will fail!
   * We allow two options for representing the accented o - the character itself,
   * and one in the unicode decomposed form with the combining acute accent.
   *
   * @const
   * @type {string}
   * @private
   */
  String _EXTN_PATTERNS_FOR_PARSING;

  String _CAPTURING_EXTN_DIGITS;

  static const _VALID_DIGITS = '0-9\uFF10-\uFF19\u0660-\u0669\u06F0-\u06F9';

  /**
   * Regular expression of viable phone numbers. This is location independent.
   * Checks we have at least three leading digits, and only valid punctuation,
   * alpha characters and digits in the phone number. Does not include extension
   * data. The symbol 'x' is allowed here as valid punctuation since it is often
   * used as a placeholder for carrier codes, for example in Brazilian phone
   * numbers. We also allow multiple '+' characters at the start.
   * Corresponds to the following:
   * [digits]{minLengthNsn}|
   * plus_sign*
   * (([punctuation]|[star])*[digits]){3,}([punctuation]|[star]|[digits]|[alpha])*
   *
   * The first reg-ex is to allow short numbers (two digits long) to be parsed if
   * they are entered as "15" etc, but only if there is no punctuation in them.
   * The second expression restricts the number of digits to three or more, but
   * then allows them to be in international form, and to have alpha-characters
   * and punctuation. We split up the two reg-exes here and combine them when
   * creating the reg-ex VALID_PHONE_NUMBER_PATTERN_ itself so we can prefix it
   * with ^ and append $ to each branch.
   *
   * Note VALID_PUNCTUATION starts with a -, so must be the first in the range.
   *
   * @const
   * @type {string}
   * @private
   */
  static const _MIN_LENGTH_PHONE_NUMBER_PATTERN = '[' + _VALID_DIGITS + ']{$_MIN_LENGTH_FOR_NSN}';

  // Regular expression of viable phone numbers. This is location independent. Checks we have at
  // least three leading digits, and only valid punctuation, alpha characters and
  // digits in the phone number. Does not include extension data.
  // The symbol 'x' is allowed here as valid punctuation since it is often used as a placeholder for
  // carrier codes, for example in Brazilian phone numbers. We also allow multiple "+" characters at
  // the start.
  // Corresponds to the following:
  // [digits]{minLengthNsn}|
  // plus_sign*(([punctuation]|[star])*[digits]){3,}([punctuation]|[star]|[digits]|[alpha])*
  //
  // The first reg-ex is to allow short numbers (two digits long) to be parsed if they are entered
  // as "15" etc, but only if there is no punctuation in them. The second expression restricts the
  // number of digits to three or more, but then allows them to be in international form, and to
  // have alpha-characters and punctuation.
  //
  // Note VALID_PUNCTUATION starts with a -, so must be the first in the range.
  String _VALID_PHONE_NUMBER;

  // Regular expression of characters typically used to start a second phone number for the purposes
  // of parsing. This allows us to strip off parts of the number that are actually the start of
  // another number, such as for: (530) 583-6985 x302/x2303 -> the second extension here makes this
  // actually two phone numbers, (530) 583-6985 x302 and (530) 583-6985 x2303. We remove the second
  // extension so that the first number is parsed correctly.
  static const _SECOND_NUMBER_START = "[\\\\/] *x";

  static final RegExp _VALID_ALPHA_PHONE_PATTERN = new RegExp(r"(?:.*?[A-Za-z]){3}.*");

  static const _RFC3966_PHONE_CONTEXT = ";phone-context=";
  static const _RFC3966_PREFIX = "tel:";
  static const _RFC3966_ISDN_SUBADDRESS = ";isub=";
  static const _RFC3966_EXTN_PREFIX = ";ext=";
  /**
   * Default extension prefix to use when formatting. This will be put in front of
   * any extension component of the number, after the main national number is
   * formatted. For example, if you wish the default extension formatting to be
   * ' extn: 3456', then you should specify ' extn: ' here as the default
   * extension prefix. This can be overridden by region-specific preferences.
   *
   * @const
   * @type {string}
   * @private
   */
  static const _DEFAULT_EXTN_PREFIX = ' ext. ';

  // We don't allow input strings for parsing to be longer than 250 chars. This prevents malicious
  // input from overflowing the regular-expression engine.
  static const REGION_CODE_FOR_NON_GEO_ENTITY = "001";

  // The PLUS_SIGN signifies the international prefix.
  static const PLUS_SIGN = '+';

  /**
   * @const
   * @type {!RegExp}
   * @private
   */
  RegExp _LEADING_PLUS_CHARS_PATTERN;

  /**
   * @const
   * @type {!RegExp}
   */
  RegExp CAPTURING_DIGIT_PATTERN;

  RegExp SECOND_NUMBER_START_PATTERN;

  RegExp _VALID_PHONE_NUMBER_PATTERN;

  RegExp PLUS_CHARS_PATTERN;

  /**
   * Regular expression of trailing characters that we want to remove. We remove
   * all characters that are not alpha or numerical characters. The hash character
   * is retained here, as it may signify the previous block was an extension.
   *
   * @const
   * @type {!RegExp}
   * @private
   */
  RegExp _UNWANTED_END_CHAR_PATTERN;

  /**
   * Regular expression of acceptable characters that may start a phone number for
   * the purposes of parsing. This allows us to strip away meaningless prefixes to
   * phone numbers that may be mistakenly given to us. This consists of digits,
   * the plus symbol and arabic-indic digits. This does not contain alpha
   * characters, although they may be used later in the number. It also does not
   * include other punctuation, as this will be stripped later during parsing and
   * is of no information value when parsing a number.
   *
   * @const
   * @type {!RegExp}
   * @private
   */
  RegExp _VALID_START_CHAR_PATTERN;

  PhoneConverter() {
    /**
     * @const
     * @type {!RegExp}
     * @private
     */
    _LEADING_PLUS_CHARS_PATTERN = new RegExp('^[' + _PLUS_CHARS + ']+');

    /**
     * @const
     * @type {!RegExp}
     */
    CAPTURING_DIGIT_PATTERN = new RegExp('([' + _VALID_DIGITS + '])');

    _CAPTURING_EXTN_DIGITS = '([' + _VALID_DIGITS + ']{1,7})';

    _EXTN_PATTERNS_FOR_PARSING = _RFC3966_EXTN_PREFIX +
        _CAPTURING_EXTN_DIGITS +
        '|' +
        '[ \u00A0\\t,]*' +
        '(?:e?xt(?:ensi(?:o\u0301?|\u00F3))?n?|\uFF45?\uFF58\uFF54\uFF4E?|' +
        '[,x\uFF58#\uFF03~\uFF5E]|int|anexo|\uFF49\uFF4E\uFF54)' +
        '[:\\.\uFF0E]?[ \u00A0\\t,-]*' +
        _CAPTURING_EXTN_DIGITS +
        '#?|' +
        '[- ]+([' +
        _VALID_DIGITS +
        ']{1,5})#';

    _EXTN_PATTERN = new RegExp("(?:" + _EXTN_PATTERNS_FOR_PARSING + "')\$", caseSensitive: false);

    _SEPARATOR_PATTERN = '[' + VALID_PUNCTUATION + ']+';

    _VALID_PHONE_NUMBER = '[' +
        _PLUS_CHARS +
        ']*(?:[' +
        VALID_PUNCTUATION +
        _STAR_SIGN +
        ']*[' +
        _VALID_DIGITS +
        ']){3,}[' +
        VALID_PUNCTUATION +
        _STAR_SIGN +
        _VALID_ALPHA +
        _VALID_DIGITS +
        ']*';

    PLUS_CHARS_PATTERN = new RegExp(r"[$PLUS_CHARS]+");

    _UNWANTED_END_CHAR_PATTERN = new RegExp('[^' + _VALID_DIGITS + _VALID_ALPHA + '#]+\$');

    SECOND_NUMBER_START_PATTERN = new RegExp(_SECOND_NUMBER_START);

    _VALID_PHONE_NUMBER_PATTERN = new RegExp(
        '^' + _MIN_LENGTH_PHONE_NUMBER_PATTERN + '\$|' + '^' + _VALID_PHONE_NUMBER + '(?:' + _EXTN_PATTERNS_FOR_PARSING + ')?' + '\$',
        caseSensitive: false);

    _VALID_START_CHAR_PATTERN = new RegExp("[" + _PLUS_CHARS + _VALID_DIGITS + "]");
    metaDataFromJSON = new BuildMetaDataFromJSON();
  }

  Future loadMetadataFromJSON(String path) {
    return metaDataFromJSON.loadMetaData(path);
  }

  /**
   * Parses a string and returns it in proto buffer format. This method will throw a
   * {@link com.google.i18n.phonenumbers.NumberParseException} if the number is not considered to be
   * a possible number. Note that validation of whether the number is actually a valid number for a
   * particular region is not performed. This can be done separately with {@link #isValidNumber}.
   *
   * @param numberToParse     number that we are attempting to parse. This can contain formatting
   *                          such as +, ( and -, as well as a phone number extension. It can also
   *                          be provided in RFC3966 format.
   * @param defaultRegion     region that we are expecting the number to be from. This is only used
   *                          if the number being parsed is not written in international format.
   *                          The country_code for the number in this case would be stored as that
   *                          of the default region supplied. If the number is guaranteed to
   *                          start with a '+' followed by the country calling code, then
   *                          "ZZ" or null can be supplied.
   * @return                  a phone number proto buffer filled with the parsed number
   */
  PhoneNumber parse(String numberToParse, {String defaultRegion: "US"}) {
    return _parseHelper(numberToParse, defaultRegion, false, false);
  }

  /**
   * Parses a string and returns it in proto buffer format. This method differs
   * from {@link #parse} in that it always populates the raw_input field of the
   * protocol buffer with numberToParse as well as the country_code_source field.
   *
   * @param {string} numberToParse number that we are attempting to parse. This
   *     can contain formatting such as +, ( and -, as well as a phone number
   *     extension.
   * @param {?string} defaultRegion region that we are expecting the number to be
   *     from. This is only used if the number being parsed is not written in
   *     international format. The country calling code for the number in this
   *     case would be stored as that of the default region supplied.
   * @return PhoneNumber a phone number proto buffer filled
   *     with the parsed number.
   * @throws {Error} if the string is not considered to be a
   *     viable phone number or if no default region was supplied.
   */
  PhoneNumber parseAndKeepRawInput(String numberToParse, String defaultRegion) {
    if (!this._isValidRegionCode(defaultRegion)) {
      if (numberToParse.isNotEmpty && numberToParse[0] != PLUS_SIGN) {
        throw ErrorType.INVALID_COUNTRY_CODE;
      }
    }
    PhoneNumber result = this._parseHelper(numberToParse, defaultRegion, true, true);
    return result;
  }

  /**
   * Parses a string and fills up the phoneNumber. This method is the same as the public
   * parse() method, with the exception that it allows the default region to be null, for use by
   * isNumberMatch(). checkRegion should be set to false if it is permitted for the default region
   * to be null or unknown ("ZZ").
   */
  PhoneNumber _parseHelper(String numberToParse, String defaultRegion, bool keepRawInput, bool checkRegion) {
    // If the user does not give any
    PhoneNumber phoneNumber = new PhoneNumber();
    if (numberToParse == null) {
      throw new NumberParseException(ErrorType.NOT_A_NUMBER, "The phone number supplied was null.");
    } else if (numberToParse.length > _MAX_INPUT_STRING_LENGTH) {
      throw new NumberParseException(ErrorType.TOO_LONG, "The string supplied was too long to parse.");
    }

    String nationalNumber = _buildNationalNumberForParsing(numberToParse);
    if (!isViablePhoneNumber(nationalNumber.toString())) {
      throw new NumberParseException(ErrorType.NOT_A_NUMBER, "The string supplied did not seem to be a phone number.");
    }

    // Check the region supplied is valid, or that the extracted number starts with some sort of +
    // sign so the number's region can be determined.
    if (checkRegion && !_checkRegionForParsing(nationalNumber.toString(), defaultRegion)) {
      throw new NumberParseException(ErrorType.INVALID_COUNTRY_CODE, "Missing or invalid default region.");
    }

    if (keepRawInput) {
      phoneNumber.setRawInput = numberToParse;
    }
    // Attempt to parse extension first, since it doesn't require region-specific data and we want
    // to have the non-normalised number here.
    nationalNumber = maybeStripExtension(nationalNumber, phoneNumber);

    PhoneMetadata regionMetadata = getMetadataForRegion(defaultRegion);

    // Check to see if the number is given in international format so we know
    // whether this number is from the default region or not.
    String normalizedNationalNumber = "";
    int countryCode = 0;
    String nationalNumberStr = nationalNumber.toString();
    try {
      countryCode = maybeExtractCountryCode(nationalNumberStr, regionMetadata, normalizedNationalNumber, keepRawInput, phoneNumber);
      if (phoneNumber.getCountryCode != 0) {
        normalizedNationalNumber = phoneNumber.getNationalNumber.toString();
      }
    } catch (e) {
      String nationalNumberStr = nationalNumber.toString();
      if (e.getErrorType() == ErrorType.INVALID_COUNTRY_CODE && _LEADING_PLUS_CHARS_PATTERN.hasMatch(nationalNumberStr)) {
        // Strip the plus-char, and try again.
        nationalNumberStr = nationalNumberStr.replaceAll(_LEADING_PLUS_CHARS_PATTERN, '');
        countryCode = maybeExtractCountryCode(nationalNumberStr, regionMetadata, normalizedNationalNumber, keepRawInput, phoneNumber);
        normalizedNationalNumber = phoneNumber.getNationalNumber.toString();

        if (countryCode == 0) {
          throw e;
        }
      } else {
        throw e;
      }
    }
    if (countryCode != 0) {
      //  String phoneNumberRegion = "US";//getRegionCodeForCountryCode(countryCode);
      String phoneNumberRegion = getRegionCodeForCountryCode(countryCode);
      if (phoneNumberRegion != defaultRegion) {
        regionMetadata = _getMetadataForRegionOrCallingCode(countryCode, phoneNumberRegion);
      }
    } else {
      // If no extracted country calling code, use the region supplied instead.
      // The national number is just the normalized version of the number we were
      // given to parse.
      normalizedNationalNumber += (_normalizeSB(nationalNumber));
      if (defaultRegion != null) {
        countryCode = regionMetadata.countryCode;
        phoneNumber.setCountryCode = countryCode;
      } else if (keepRawInput) {
        phoneNumber.setCountryCodeSource = null;
      }
    }

    if (regionMetadata != null) {
      String carrierCode = "";
      String potentialNationalNumber = normalizedNationalNumber.toString();
      maybeStripNationalPrefixAndCarrierCode(potentialNationalNumber, regionMetadata, carrierCode);
      if (!_isShorterThanPossibleNormalNumber(regionMetadata, potentialNationalNumber.toString())) {
        normalizedNationalNumber = potentialNationalNumber;
        if (keepRawInput) {
          phoneNumber.setPreferredDomesticCarrierCode = carrierCode.toString();
        }
      }
    }
    String normalizedNationalNumberStr = normalizedNationalNumber.toString();
    int lengthOfNationalNumber = normalizedNationalNumberStr.length;
    if (lengthOfNationalNumber < _MIN_LENGTH_FOR_NSN) {
      throw ErrorType.TOO_SHORT_NSN;
    }
    if (lengthOfNationalNumber > _MAX_LENGTH_FOR_NSN) {
      throw ErrorType.TOO_LONG;
    }
    _setItalianLeadingZerosForPhoneNumber(normalizedNationalNumberStr, phoneNumber);

    phoneNumber.setNationalNumber = int.parse(normalizedNationalNumber);
    phoneNumber.setCountryCodeSource = CountryCodeSource.FROM_NUMBER_WITHOUT_PLUS_SIGN;
    if (keepRawInput) {
      phoneNumber.setRawInput = numberToParse;
    }
    return phoneNumber;
  }

  /**
   * A helper function to set the values related to leading zeros in a
   * PhoneNumber.
   *
   * @param {string} nationalNumber the number we are parsing.
   * @param PhoneNumber phoneNumber a phone number proto
   *     buffer to fill in.
   * @private
   */
  void _setItalianLeadingZerosForPhoneNumber(String nationalNumber, PhoneNumber phoneNumber) {
    if (nationalNumber.length > 1 && nationalNumber[0] == '0') {
      phoneNumber.setItalianLeadingZero = true;
      int numberOfLeadingZeros = 1;
      // Note that if the national number is all "0"s, the last "0" is not counted
      // as a leading zero.
      while (numberOfLeadingZeros < nationalNumber.length - 1 && nationalNumber[numberOfLeadingZeros] == '0') {
        numberOfLeadingZeros++;
      }
      if (numberOfLeadingZeros != 1) {
        phoneNumber.setNumberOfLeadingZeros = numberOfLeadingZeros;
      }
    }
  }

  /**
   * Checks whether countryCode represents the country calling code from a region
   * whose national significant number could contain a leading zero. An example of
   * such a region is Italy. Returns false if no metadata for the country is
   * found.
   *
   * @param {number} countryCallingCode the country calling code.
   * @return {boolean}
   */
  bool isLeadingZeroPossible(int countryCallingCode) {
    PhoneMetadata mainMetadataForCallingCode =
        this._getMetadataForRegionOrCallingCode(countryCallingCode, this.getRegionCodeForCountryCode(countryCallingCode));
    return mainMetadataForCallingCode != null && (mainMetadataForCallingCode.leadingZeroPossible ?? false);
  }

  /**
   * Checks if this is a region under the North American Numbering Plan
   * Administration (NANPA).
   *
   * @param {?string} regionCode the ISO 3166-1 two-letter region code.
   * @return {boolean} true if regionCode is one of the regions under NANPA.
   */
  bool isNANPACountry(String regionCode) {
    return regionCode != null && DefaultPhoneRegionData.countryCodeToRegionCodeMap[_NANPA_COUNTRY_CODE].contains(regionCode.toUpperCase());
  }

  /**
   * Gets the national significant number of the a phone number. Note a national
   * significant number doesn't contain a national prefix or any formatting.
   *
   * @param PhoneNumber number the phone number for which the
   *     national significant number is needed.
   * @return {string} the national significant number of the PhoneNumber object
   *     passed in.
   */
  String getNationalSignificantNumber(PhoneNumber number) {
    // If leading zero(s) have been set, we prefix this now. Note this is not a
    // national prefix.
    String nationalNumber = '' + number.getNationalNumber.toString();
    if (number.getItalianLeadingZero) {
      String result = "";
      for (int i = 0; i < number.getNumberOfLeadingZeros; i++) {
        result += '0';
      }
      return result + nationalNumber;
    }
    return nationalNumber;
  }

  /**
   * Formats a phone number for out-of-country dialing purposes. If no
   * regionCallingFrom is supplied, we format the number in its INTERNATIONAL
   * format. If the country calling code is the same as that of the region where
   * the number is from, then NATIONAL formatting will be applied.
   *
   * <p>If the number itself has a country calling code of zero or an otherwise
   * invalid country calling code, then we return the number with no formatting
   * applied.
   *
   * <p>Note this function takes care of the case for calling inside of NANPA and
   * between Russia and Kazakhstan (who share the same country calling code). In
   * those cases, no international prefix is used. For regions which have multiple
   * international prefixes, the number in its INTERNATIONAL format will be
   * returned instead.
   *
   * @param PhoneNumber number the phone number to be
   *     formatted.
   * @param {string} regionCallingFrom the region where the call is being placed.
   * @return {string} the formatted phone number.
   */
  String formatOutOfCountryCallingNumber(PhoneNumber number, String regionCallingFrom) {
    if (!this._isValidRegionCode(regionCallingFrom)) {
      return this.format(number, PhoneNumberFormat.INTERNATIONAL);
    }
    int countryCallingCode = number.getCountryCode;
    String nationalSignificantNumber = this.getNationalSignificantNumber(number);
    if (!this._hasValidCountryCallingCode(countryCallingCode)) {
      return nationalSignificantNumber;
    }
    if (countryCallingCode == _NANPA_COUNTRY_CODE) {
      if (this.isNANPACountry(regionCallingFrom)) {
        // For NANPA regions, return the national format for these regions but
        // prefix it with the country calling code.
        return countryCallingCode.toString() + ' ' + this.format(number, PhoneNumberFormat.NATIONAL);
      }
    } else if (countryCallingCode == this._getCountryCodeForValidRegion(regionCallingFrom)) {
      // If regions share a country calling code, the country calling code need
      // not be dialled. This also applies when dialling within a region, so this
      // if clause covers both these cases. Technically this is the case for
      // dialling from La Reunion to other overseas departments of France (French
      // Guiana, Martinique, Guadeloupe), but not vice versa - so we don't cover
      // this edge case for now and for those cases return the version including
      // country calling code. Details here:
      // http://www.petitfute.com/voyage/225-info-pratiques-reunion
      return this.format(number, PhoneNumberFormat.NATIONAL);
    }
    // Metadata cannot be null because we checked 'isValidRegionCode()' above.
    PhoneMetadata metadataForRegionCallingFrom = this.getMetadataForRegion(regionCallingFrom);
    String internationalPrefix = metadataForRegionCallingFrom.internationalPrefix ?? '';

    // For regions that have multiple international prefixes, the international
    // format of the number is returned, unless there is a preferred international
    // prefix.
    String internationalPrefixForFormatting = '';
    if (_matchesEntirely(_UNIQUE_INTERNATIONAL_PREFIX, internationalPrefix)) {
      internationalPrefixForFormatting = internationalPrefix;
    } else if (metadataForRegionCallingFrom.hasPreferredInternationalPrefix()) {
      internationalPrefixForFormatting = metadataForRegionCallingFrom.preferredInternationalPrefix;
    }

    String regionCode = this.getRegionCodeForCountryCode(countryCallingCode);
    // Metadata cannot be null because the country calling code is valid.
    PhoneMetadata metadataForRegion = this._getMetadataForRegionOrCallingCode(countryCallingCode, regionCode);
    String formattedNationalNumber = this._formatNsn(nationalSignificantNumber, metadataForRegion, PhoneNumberFormat.INTERNATIONAL);
    String formattedExtension = this._maybeGetFormattedExtension(number, metadataForRegion, PhoneNumberFormat.INTERNATIONAL);
    return internationalPrefixForFormatting.isNotEmpty
        ? internationalPrefixForFormatting + ' ' + countryCallingCode.toString() + ' ' + formattedNationalNumber + formattedExtension
        : this._prefixNumberWithCountryCallingCode(
            countryCallingCode, PhoneNumberFormat.INTERNATIONAL, formattedNationalNumber, formattedExtension);
  }

  /**
   * Returns the country calling code for a specific region. For example, this
   * would be 1 for the United States, and 64 for New Zealand. Assumes the region
   * is already valid.
   *
   * @param {?string} regionCode the region that we want to get the country
   *     calling code for.
   * @return {number} the country calling code for the region denoted by
   *     regionCode.
   * @throws {string} if the region is invalid
   * @private
   */
  int _getCountryCodeForValidRegion(String regionCode) {
    PhoneMetadata metadata = this.getMetadataForRegion(regionCode);

    if (metadata == null) {
      throw 'Invalid region code: ' + regionCode.toString();
    }
    return metadata.countryCode;
  }

  /**
   * Returns the national dialling prefix for a specific region. For example, this
   * would be 1 for the United States, and 0 for New Zealand. Set stripNonDigits
   * to true to strip symbols like '~' (which indicates a wait for a dialling
   * tone) from the prefix returned. If no national prefix is present, we return
   * null.
   *
   * <p>Warning: Do not use this method for do-your-own formatting - for some
   * regions, the national dialling prefix is used only for certain types of
   * numbers. Use the library's formatting functions to prefix the national prefix
   * when required.
   *
   * @param {?string} regionCode the region that we want to get the dialling
   *     prefix for.
   * @param {boolean} stripNonDigits true to strip non-digits from the national
   *     dialling prefix.
   * @return {?string} the dialling prefix for the region denoted by
   *     regionCode.
   */
  String getNddPrefixForRegion(String regionCode, bool stripNonDigits) {
    PhoneMetadata metadata = this.getMetadataForRegion(regionCode);
    if (metadata == null) {
      return null;
    }
    String nationalPrefix = metadata.nationalPrefix;
    // If no national prefix was found, we return null.
    if (nationalPrefix.isEmpty) {
      return null;
    }
    if (stripNonDigits) {
      // Note: if any other non-numeric symbols are ever used in national
      // prefixes, these would have to be removed here as well.
      nationalPrefix = nationalPrefix.replaceFirst('~', '');
    }
    return nationalPrefix;
  }

  /**
   * Tests whether a phone number matches a valid pattern. Note this doesn't
   * verify the number is actually in use, which is impossible to tell by just
   * looking at a number itself.
   *
   * @param PhoneNumber number the phone number that we want
   *     to validate.
   * @return {boolean} a boolean that indicates whether the number is of a valid
   *     pattern.
   */
  bool isValidNumber(PhoneNumber number) {
    String regionCode = this.getRegionCodeForNumber(number);
    return this.isValidNumberForRegion(number, regionCode);
  }

  /**
   * Tests whether a phone number is valid for a certain region. Note this doesn't
   * verify the number is actually in use, which is impossible to tell by just
   * looking at a number itself. If the country calling code is not the same as
   * the country calling code for the region, this immediately exits with false.
   * After this, the specific number pattern rules for the region are examined.
   * This is useful for determining for example whether a particular number is
   * valid for Canada, rather than just a valid NANPA number.
   * Warning: In most cases, you want to use {@link #isValidNumber} instead. For
   * example, this method will mark numbers from British Crown dependencies such
   * as the Isle of Man as invalid for the region "GB" (United Kingdom), since it
   * has its own region code, "IM", which may be undesirable.
   *
   * @param PhoneNumber number the phone number that we want
   *     to validate.
   * @param {?string} regionCode the region that we want to validate the phone
   *     number for.
   * @return {boolean} a boolean that indicates whether the number is of a valid
   *     pattern.
   */
  bool isValidNumberForRegion(PhoneNumber number, String regionCode) {
    if (regionCode == null) {
      return false;
    }
    int countryCode = number.getCountryCode;

    PhoneMetadata metadata = this._getMetadataForRegionOrCallingCode(countryCode, regionCode);
    int retrieveCountryCode = this._getCountryCodeForValidRegion(regionCode);
    if (metadata == null || (REGION_CODE_FOR_NON_GEO_ENTITY != regionCode && countryCode != retrieveCountryCode)) {
      // Either the region code was invalid, or the country calling code for this
      // number does not match that of the region code.
      return false;
    }
    String nationalSignificantNumber = this.getNationalSignificantNumber(number);

    return this._getNumberTypeHelper(nationalSignificantNumber, metadata) != PhoneNumberType.UNKNOWN;
  }

  /**
   * @param {string} nationalNumber
   * @param PhoneMetadata metadata
   * @return PhoneNumberType
   * @private
   */
  PhoneNumberType _getNumberTypeHelper(String nationalNumber, PhoneMetadata metadata) {
    if (!this._isNumberMatchingDesc(nationalNumber, metadata.generalDesc)) {
      return PhoneNumberType.UNKNOWN;
    }

    if (this._isNumberMatchingDesc(nationalNumber, metadata.premiumRate)) {
      return PhoneNumberType.PREMIUM_RATE;
    }
    if (this._isNumberMatchingDesc(nationalNumber, metadata.tollFree)) {
      return PhoneNumberType.TOLL_FREE;
    }
    if (this._isNumberMatchingDesc(nationalNumber, metadata.sharedCost)) {
      return PhoneNumberType.SHARED_COST;
    }
    if (this._isNumberMatchingDesc(nationalNumber, metadata.voip)) {
      return PhoneNumberType.VOIP;
    }
    if (this._isNumberMatchingDesc(nationalNumber, metadata.personalNumber)) {
      return PhoneNumberType.PERSONAL_NUMBER;
    }
    if (this._isNumberMatchingDesc(nationalNumber, metadata.pager)) {
      return PhoneNumberType.PAGER;
    }
    if (this._isNumberMatchingDesc(nationalNumber, metadata.uan)) {
      return PhoneNumberType.UAN;
    }
    if (this._isNumberMatchingDesc(nationalNumber, metadata.voicemail)) {
      return PhoneNumberType.VOICEMAIL;
    }

    bool isFixedLine = this._isNumberMatchingDesc(nationalNumber, metadata.fixedLine);
    if (isFixedLine) {
      if (metadata.sameMobileAndFixedLinePattern) {
        return PhoneNumberType.FIXED_LINE_OR_MOBILE;
      } else if (this._isNumberMatchingDesc(nationalNumber, metadata.mobile)) {
        return PhoneNumberType.FIXED_LINE_OR_MOBILE;
      }
      return PhoneNumberType.FIXED_LINE;
    }
    // Otherwise, test to see if the number is mobile. Only do this if certain
    // that the patterns for mobile and fixed line aren't the same.
    if (!metadata.sameMobileAndFixedLinePattern && this._isNumberMatchingDesc(nationalNumber, metadata.mobile)) {
      return PhoneNumberType.MOBILE;
    }
    return PhoneNumberType.UNKNOWN;
  }

  /**
   * @param {string} nationalNumber
   * @param PhoneNumberDesc numberDesc
   * @return {boolean}
   * @private
   */
  bool _isNumberMatchingDesc(String nationalNumber, PhoneNumberDesc numberDesc) {
    return _matchesEntirely(new RegExp(numberDesc.possibleNumberPattern), nationalNumber) &&
        _matchesEntirely(new RegExp(numberDesc.nationalNumberPattern), nationalNumber);
  }

  /**
   * Returns the region where a phone number is from. This could be used for
   * geocoding at the region level.
   *
   * @param PhoneNumber number the phone number whose origin
   *     we want to know.
   * @return {?string} the region where the phone number is from, or null
   *     if no region matches this calling code.
   */
  String getRegionCodeForNumber(PhoneNumber number) {
    if (number == null) {
      return null;
    }
    int countryCode = number.getCountryCode;
    List<String> regions = DefaultPhoneRegionData.countryCodeToRegionCodeMap[countryCode];
    if (regions == null) {
      return null;
    }
    if (regions.length == 1) {
      return regions[0];
    } else {
      return this._getRegionCodeForNumberFromRegionList(number, regions);
    }
  }

  /**
   * @param PhoneNumber number
   * @param {List.<string>} regionCodes
   * @return {?string}
   * @private
   */
  String _getRegionCodeForNumberFromRegionList(PhoneNumber number, List<String> regionCodes) {
    String nationalNumber = this.getNationalSignificantNumber(number);
    String regionCode;
    int regionCodesLength = regionCodes.length;
    for (int i = 0; i < regionCodesLength; i++) {
      regionCode = regionCodes[i];
      // If leadingDigits is present, use this. Otherwise, do full validation.
      // Metadata cannot be null because the region codes come from the country
      // calling code map.
      PhoneMetadata metadata = this.getMetadataForRegion(regionCode);
      if (metadata.hasLeadingDigits()) {
        if (nationalNumber.startsWith(new RegExp(metadata.leadingDigits))) {
          return regionCode;
        }
      } else if (this._getNumberTypeHelper(nationalNumber, metadata) != PhoneNumberType.UNKNOWN) {
        return regionCode;
      }
    }
    return null;
  }

  /**
   * Helper method to check whether a number is too short to be a regular length
   * phone number in a region.
   *
   * @param PhoneMetadata regionMetadata
   * @param {string} number
   * @return {boolean}
   * @private
   */
  bool _isShorterThanPossibleNormalNumber(PhoneMetadata regionMetadata, String number) {
    String possibleNumberPattern = regionMetadata.generalDesc.possibleNumberPattern;
    return _testNumberLengthAgainstPattern(possibleNumberPattern, number) == ValidationResult.TOO_SHORT;
  }

  /**
   * Tries to extract a country calling code from a number. This method will return zero if no
   * country calling code is considered to be present. Country calling codes are extracted in the
   * following ways:
   * <ul>
   *  <li> by stripping the international dialing prefix of the region the person is dialing from,
   *       if this is present in the number, and looking at the next digits
   *  <li> by stripping the '+' sign if present and then looking at the next digits
   *  <li> by comparing the start of the number and the country calling code of the default region.
   *       If the number is not considered possible for the numbering plan of the default region
   *       initially, but starts with the country calling code of this region, validation will be
   *       reattempted after stripping this country calling code. If this number is considered a
   *       possible number, then the first digits will be considered the country calling code and
   *       removed as such.
   * </ul>
   * It will throw a NumberParseException if the number starts with a '+' but the country calling
   * code supplied after this does not match that of any known region.
   *
   * @param number  non-normalized telephone number that we wish to extract a country calling
   *     code from - may begin with '+'
   * @param defaultRegionMetadata  metadata about the region this number may be from
   * @param nationalNumber  a string buffer to store the national significant number in, in the case
   *     that a country calling code was extracted. The number is appended to any existing contents.
   *     If no country calling code was extracted, this will be left unchanged.
   * @param keepRawInput  true if the country_code_source and preferred_carrier_code fields of
   *     phoneNumber should be populated.
   * @param phoneNumber  the PhoneNumber object where the country_code and country_code_source need
   *     to be populated. Note the country_code is always populated, whereas country_code_source is
   *     only populated when keepCountryCodeSource is true.
   * @return  the country calling code extracted or 0 if none could be extracted
   */
  int maybeExtractCountryCode(
      String number, PhoneMetadata defaultRegionMetadata, String nationalNumber, bool keepRawInput, PhoneNumber phoneNumber) {
    if (number.isEmpty) {
      return 0;
    }
    String fullNumber = number;
    // Set the default prefix to be something that will never match.
    String possibleCountryIddPrefix = "NonMatch";
    if (defaultRegionMetadata != null) {
      possibleCountryIddPrefix = defaultRegionMetadata.internationalPrefix;
    }

    fullNumber = maybeStripInternationalPrefixAndNormalize(fullNumber, possibleCountryIddPrefix, phoneNumber);
    CountryCodeSource countryCodeSource = phoneNumber.getCountryCodeSource;
    if (keepRawInput) {
      phoneNumber.setCountryCodeSource = countryCodeSource;
    }
    if (countryCodeSource != CountryCodeSource.FROM_DEFAULT_COUNTRY) {
      if (fullNumber.length <= _MIN_LENGTH_FOR_NSN) {
        throw new NumberParseException(
            ErrorType.TOO_SHORT_AFTER_IDD, "Phone number had an IDD, but after this was not " + "long enough to be a viable phone number.");
      }
      int potentialCountryCode = extractCountryCode(fullNumber, nationalNumber, phoneNumber);
      nationalNumber = phoneNumber.getNationalNumber.toString();
      if (potentialCountryCode != 0) {
        phoneNumber.setNationalNumber = int.parse(nationalNumber);
        phoneNumber.setCountryCode = potentialCountryCode;
        return potentialCountryCode;
      }

      // If this fails, they must be using a strange country calling code that we don't recognize,
      // or that doesn't exist.
      throw new NumberParseException(ErrorType.INVALID_COUNTRY_CODE, "Country calling code supplied was not recognised.");
    } else if (defaultRegionMetadata != null) {
      // Check to see if the number starts with the country calling code for the default region. If
      // so, we remove the country calling code, and do some checks on the validity of the number
      // before and after.
      // Check to see if the number starts with the country calling code for the
      // default region. If so, we remove the country calling code, and do some
      // checks on the validity of the number before and after.
      int defaultCountryCode = defaultRegionMetadata.countryCode;
      String defaultCountryCodeString = defaultCountryCode.toString();
      String normalizedNumber = fullNumber.toString();
      if (normalizedNumber.startsWith(defaultCountryCodeString)) {
        String potentialNationalNumber = normalizedNumber.substring(defaultCountryCodeString.length);

        PhoneNumberDesc generalDesc = defaultRegionMetadata.generalDesc;
        RegExp validNumberPattern = new RegExp(generalDesc.nationalNumberPattern);
        // Passing null since we don't need the carrier code.
        maybeStripNationalPrefixAndCarrierCode(potentialNationalNumber, defaultRegionMetadata, null);
        String potentialNationalNumberStr = potentialNationalNumber.toString();
        String possibleNumberPattern = generalDesc.possibleNumberPattern;
        // If the number was not valid before but is valid now, or if it was too
        // long before, we consider the number with the country calling code
        // stripped to be a better result and keep that instead.
        if ((!_matchesEntirely(validNumberPattern, fullNumber.toString()) &&
                _matchesEntirely(validNumberPattern, potentialNationalNumberStr)) ||
            _testNumberLengthAgainstPattern(possibleNumberPattern, fullNumber.toString()) == ValidationResult.TOO_LONG) {
          nationalNumber += potentialNationalNumberStr;
          if (keepRawInput) {
            phoneNumber.setCountryCodeSource = CountryCodeSource.FROM_NUMBER_WITHOUT_PLUS_SIGN;
          }
          phoneNumber.setNationalNumber = int.parse(nationalNumber);
          phoneNumber.setCountryCode = defaultCountryCode;
          return defaultCountryCode;
        }
      }
      phoneNumber.setNationalNumber = int.parse(normalizedNumber);
    }
    // No country calling code present.
    phoneNumber.setCountryCode = 0;
    return 0;
  }

  /**
   * Strips any national prefix (such as 0, 1) present in the number provided.
   *
   * @param {!goog.string.StringBuffer} number the normalized telephone number
   *     that we wish to strip any national dialing prefix from.
   * @param PhoneMetadata metadata the metadata for the
   *     region that we think this number is from.
   * @param {goog.string.StringBuffer} carrierCode a place to insert the carrier
   *     code if one is extracted.
   * @return {boolean} true if a national prefix or carrier code (or both) could
   *     be extracted.
   */
  bool maybeStripNationalPrefixAndCarrierCode(String number, PhoneMetadata metadata, String carrierCode) {
    String numberStr = number.toString();
    String possibleNationalPrefix = metadata.nationalPrefixForParsing;
    if (numberStr.isEmpty || possibleNationalPrefix == null || possibleNationalPrefix.isEmpty) {
      // Early return for numbers of zero length.
      return false;
    }
    // Attempt to parse the first digits as a national prefix.
    RegExp prefixPattern = new RegExp('^(?:' + possibleNationalPrefix + ')');
    Match prefixMatcher = prefixPattern.firstMatch(numberStr);
    if (prefixMatcher != null) {
      RegExp nationalNumberRule = new RegExp(metadata.generalDesc.nationalNumberPattern);
      // Check if the original number is viable.
      bool isViableOriginalNumber = _matchesEntirely(nationalNumberRule, numberStr);
      // prefixMatcher[numOfGroups] == null implies nothing was captured by the
      // capturing groups in possibleNationalPrefix; therefore, no transformation
      // is necessary, and we just remove the national prefix.
      int numOfGroups = prefixMatcher.groupCount - 1;
      String transformRule = metadata.nationalPrefixTransformRule;
      bool noTransform = transformRule == null ||
          transformRule.isEmpty ||
          prefixMatcher[numOfGroups] == null ||
          prefixMatcher[numOfGroups].isEmpty;
      if (noTransform) {
        // If the original number was viable, and the resultant number is not,
        // we return.
        if (isViableOriginalNumber && !_matchesEntirely(nationalNumberRule, numberStr.substring(prefixMatcher[0].length))) {
          return false;
        }
        if (carrierCode != null && numOfGroups > 0 && prefixMatcher[numOfGroups] != null) {
          carrierCode += (prefixMatcher[1]);
        }
        number = (numberStr.substring(prefixMatcher[0].length));
        return true;
      } else {
        // Check that the resultant number is still viable. If not, return. Check
        // this by copying the string buffer and making the transformation on the
        // copy first.
        String transformedNumber = numberStr.replaceAll(prefixPattern, transformRule);
        if (isViableOriginalNumber && !_matchesEntirely(nationalNumberRule, transformedNumber)) {
          return false;
        }
        if (carrierCode != null && numOfGroups > 0) {
          carrierCode += (prefixMatcher[1]);
        }
        number = (transformedNumber);
        return true;
      }
    }
    return false;
  }

  ValidationResult _testNumberLengthAgainstPattern(String numberPattern, String number) {
    RegExp numberExp = new RegExp(numberPattern);
    if (_matchesEntirely(numberExp, number)) {
      return ValidationResult.IS_POSSIBLE;
    }
    if (number.startsWith(numberExp)) {
      return ValidationResult.TOO_LONG;
    } else {
      return ValidationResult.TOO_SHORT;
    }
  }

  /**
     * Strips any international prefix (such as +, 00, 011) present in the number
     * provided, normalizes the resulting number, and indicates if an international
     * prefix was present.
     *
     * @param {!goog.string.StringBuffer} number the non-normalized telephone number
     *     that we wish to strip any international dialing prefix from.
     * @param {string} possibleIddPrefix the international direct dialing prefix
     *     from the region we think this number may be dialed in.
     * @return {i18n.phonenumbers.PhoneNumber.CountryCodeSource} the corresponding
     *     CountryCodeSource if an international dialing prefix could be removed
     *     from the number, otherwise CountryCodeSource.FROM_DEFAULT_COUNTRY if
     *     the number did not seem to be in international format.
     */
  String maybeStripInternationalPrefixAndNormalize(String number, String possibleIddPrefix, PhoneNumber phoneNumber) {
    String numberStr = number.toString();
    if (numberStr.isEmpty) {
      phoneNumber.setCountryCodeSource = CountryCodeSource.FROM_DEFAULT_COUNTRY;
      return number;
    }
    // Check to see if the number begins with one or more plus signs.
    if (_LEADING_PLUS_CHARS_PATTERN.hasMatch(numberStr)) {
      numberStr = numberStr.replaceAll(_LEADING_PLUS_CHARS_PATTERN, '');
      // Can now normalize the rest of the number since we've consumed the '+'
      // sign at the start.
      number += (normalize(numberStr));
      phoneNumber.setCountryCodeSource = CountryCodeSource.FROM_NUMBER_WITH_PLUS_SIGN;
      return number;
    }
    // Attempt to parse the first digits as an international prefix.
    RegExp iddPattern = new RegExp(possibleIddPrefix);
    number = _normalizeSB(number);
    number = _parsePrefixAsIdd(iddPattern, number, phoneNumber);
    return number;
  }

  /**
   * Strips the IDD from the start of the number if present. Helper function used
   * by maybeStripInternationalPrefixAndNormalize.
   *
   * @param {!RegExp} iddPattern the regular expression for the international
   *     prefix.
   * @param {!goog.string.StringBuffer} number the phone number that we wish to
   *     strip any international dialing prefix from.
   * @return {boolean} true if an international prefix was present.
   * @private
   */
  String _parsePrefixAsIdd(RegExp iddPattern, String number, PhoneNumber phoneNumber) {
    String numberStr = number.toString();
    if (numberStr.startsWith(iddPattern)) {
      int matchEnd = iddPattern.firstMatch(numberStr)[0].length;
      Match matchedGroups = CAPTURING_DIGIT_PATTERN.firstMatch(numberStr.substring(matchEnd));
      if (matchedGroups != null && matchedGroups[1] != null && matchedGroups[1].isNotEmpty) {
        String normalizedGroup = normalizeDigitsOnly(matchedGroups[1]);
        if (normalizedGroup == '0') {
          phoneNumber.setCountryCodeSource = CountryCodeSource.FROM_DEFAULT_COUNTRY;
          return number;
        }
      }
      number = (numberStr.substring(matchEnd));
      phoneNumber.setCountryCodeSource = CountryCodeSource.FROM_NUMBER_WITH_IDD;
      return number;
    }
    phoneNumber.setCountryCodeSource = CountryCodeSource.FROM_DEFAULT_COUNTRY;
    return number;
  }

  /**
     * Extracts country calling code from fullNumber, returns it and places the
     * remaining number in nationalNumber. It assumes that the leading plus sign or
     * IDD has already been removed. Returns 0 if fullNumber doesn't start with a
     * valid country calling code, and leaves nationalNumber unmodified.
     *
     * @param {!goog.string.StringBuffer} fullNumber
     * @param {!goog.string.StringBuffer} nationalNumber
     * @return {number}
     */
  int extractCountryCode(String fullNumber, String nationalNumber, PhoneNumber phoneNumber) {
    String fullNumberStr = fullNumber.toString();
    if ((fullNumberStr.isEmpty) || (fullNumberStr[0] == '0')) {
      // Country codes do not begin with a '0'.
      return 0;
    }
    int potentialCountryCode;
    int numberLength = fullNumberStr.length;
    for (int i = 1; i <= _MAX_LENGTH_COUNTRY_CODE && i <= numberLength; ++i) {
      potentialCountryCode = int.parse(fullNumberStr.substring(0, i), radix: 10);
      if (DefaultPhoneRegionData.countryCodeToRegionCodeMap.containsKey(potentialCountryCode)) {
        nationalNumber += (fullNumberStr.substring(i));
        phoneNumber.setNationalNumber = int.parse(nationalNumber);
        return potentialCountryCode;
      }
    }
    return 0;
  }

  /**
   * Checks to see that the region code used is valid, or if it is not valid, that the number to
   * parse starts with a + symbol so that we can attempt to infer the region from the number.
   * Returns false if it cannot use the region provided and the region cannot be inferred.
   */
  bool _checkRegionForParsing(String numberToParse, String defaultRegion) {
    if (!_isValidRegionCode(defaultRegion)) {
      // If the number is null or empty, we can't infer the region.
      if ((numberToParse == null) || (numberToParse.isEmpty) || PLUS_CHARS_PATTERN.matchAsPrefix(numberToParse) == null) {
        return false;
      }
    }
    return true;
  }

  /**
   * Helper function to check region code is not unknown or null.
   */
  bool _isValidRegionCode(String regionCode) {
    //TODO: IMPLEMENT SUPPORTED REGIONS
    return regionCode != null; //&& supportedRegions.contains(regionCode);
  }

  /**
   * Checks to see if the string of characters could possibly be a phone number at all. At the
   * moment, checks to see that the string begins with at least 2 digits, ignoring any punctuation
   * commonly found in phone numbers.
   * This method does not require the number to be normalized in advance - but does assume that
   * leading non-number symbols have been removed, such as by the method extractPossibleNumber.
   *
   * @param number  string to be checked for viability as a phone number
   * @return        true if the number could be a phone number of some sort, otherwise false
   */
  bool isViablePhoneNumber(String number) {
    if (number.length < _MIN_LENGTH_FOR_NSN) {
      return false;
    }
    return _VALID_PHONE_NUMBER_PATTERN.hasMatch(number);
  }

  /**
   * Converts numberToParse to a form that we can parse and write it to nationalNumber if it is
   * written in RFC3966; otherwise extract a possible number out of it and write to nationalNumber.
   */
  String _buildNationalNumberForParsing(String numberToParse) {
    String nationalNumber = "";
    int indexOfPhoneContext = numberToParse.indexOf(_RFC3966_PHONE_CONTEXT);
    if (indexOfPhoneContext > 0) {
      int phoneContextStart = indexOfPhoneContext + _RFC3966_PHONE_CONTEXT.length;
      // If the phone context contains a phone number prefix, we need to capture it, whereas domains
      // will be ignored.
      if (numberToParse[phoneContextStart] == PLUS_SIGN) {
        // Additional parameters might follow the phone context. If so, we will remove them here
        // because the parameters after phone context are not important for parsing the
        // phone number.
        int phoneContextEnd = numberToParse.indexOf(';', phoneContextStart);
        if (phoneContextEnd > 0) {
          nationalNumber += (numberToParse.substring(phoneContextStart, phoneContextEnd));
        } else {
          nationalNumber += (numberToParse.substring(phoneContextStart));
        }
      }

      // Now append everything between the "tel:" prefix and the phone-context. This should include
      // the national number, an optional extension or isdn-subaddress component. Note we also
      // handle the case when "tel:" is missing, as we have seen in some of the phone number inputs.
      // In that case, we append everything from the beginning.
      int indexOfRfc3966Prefix = numberToParse.indexOf(_RFC3966_PREFIX);
      int indexOfNationalNumber = (indexOfRfc3966Prefix >= 0) ? indexOfRfc3966Prefix + _RFC3966_PREFIX.length : 0;
      nationalNumber += (numberToParse.substring(indexOfNationalNumber, indexOfPhoneContext));
    } else {
      // Extract a possible number from the string passed in (this strips leading characters that
      // could not be the start of a phone number.)
      nationalNumber += (extractPossibleNumber(numberToParse));
    }

    // Delete the isdn-subaddress and everything after it if it is present. Note extension won't
    // appear at the same time with isdn-subaddress according to paragraph 5.3 of the RFC3966 spec,
    int indexOfIsdn = nationalNumber.indexOf(_RFC3966_ISDN_SUBADDRESS);
    if (indexOfIsdn > 0) {
      //nationalNumber.delete(indexOfIsdn, nationalNumber.length);
      nationalNumber = nationalNumber.substring(0, indexOfIsdn);
    }
    // If both phone context and isdn-subaddress are absent but other parameters are present, the
    // parameters are left in nationalNumber. This is because we are concerned about deleting
    // content from a potential number string when there is no strong evidence that the number is
    // actually written in RFC3966.
    return nationalNumber;
  }

  /**
   * Strips any extension (as in, the part of the number dialled after the call is connected,
   * usually indicated with extn, ext, x or similar) from the end of the number, and returns it.
   *
   * @param number  the non-normalized telephone number that we wish to strip the extension from
   * @return        the phone extension
   */
  String maybeStripExtension(String number, PhoneNumber phoneNumber) {
    bool findMatch = _EXTN_PATTERN.hasMatch(number);
    Match m = _EXTN_PATTERN.firstMatch(number);
    // If we find a potential extension, and the number preceding this is a viable number, we assume
    // it is an extension.
    if (findMatch && isViablePhoneNumber(number.substring(0, m.start))) {
      // The numbers are captured into groups in the regular expression.
      for (int i = 1, length = m.groupCount; i <= length; i++) {
        if (m.group(i) != null) {
          // We go through the capturing groups until we find one that captured some digits. If none
          // did, then we will return the empty string.
          String extension = m.group(i);
          number = number.substring(0, m.start);
          if (extension.isNotEmpty) {
            phoneNumber.setExtension = extension;
          }
          return number;
        }
      }
    }
    return number;
  }

  /**
   * Attempts to extract a possible number from the string passed in. This currently strips all
   * leading characters that cannot be used to start a phone number. Characters that can be used to
   * start a phone number are defined in the VALID_START_CHAR_PATTERN. If none of these characters
   * are found in the number passed in, an empty string is returned. This function also attempts to
   * strip off any alternative extensions or endings if two or more are present, such as in the case
   * of: (530) 583-6985 x302/x2303. The second extension here makes this actually two phone numbers,
   * (530) 583-6985 x302 and (530) 583-6985 x2303. We remove the second extension so that the first
   * number is parsed correctly.
   *
   * @param number  the string that might contain a phone number
   * @return        the number, stripped of any non-phone-number prefix (such as "Tel:") or an empty
   *                string if no character used to start phone numbers (such as + or any digit) is
   *                found in the number
   */
  String extractPossibleNumber(String number) {
    Match m = _VALID_START_CHAR_PATTERN.firstMatch(number);
    if (_VALID_START_CHAR_PATTERN.hasMatch(number)) {
      number = number.substring(m.start);
      // Remove trailing non-alpha non-numerical characters.

      Match trailingCharsMatch = _UNWANTED_END_CHAR_PATTERN.firstMatch(number);
      if (_UNWANTED_END_CHAR_PATTERN.hasMatch(number)) {
        number = number.substring(0, trailingCharsMatch.start);
        logger.fine("Stripped trailing characters: $number");
      }
      // Check for extra numbers at the end.
      Match secondNumber = SECOND_NUMBER_START_PATTERN.firstMatch(number);
      if (SECOND_NUMBER_START_PATTERN.hasMatch(number)) {
        number = number.substring(0, secondNumber.start);
      }
      return number;
    } else {
      return "";
    }
  }

  String formatNumber(String number, PhoneNumberFormat numberFormat, {defaultRegion: "US"}) {
    return format(parse(number, defaultRegion: defaultRegion), numberFormat, defaultRegion: defaultRegion);
  }

  /**
   * Formats a phone number in the specified format using default rules. Note that this does not
   * promise to produce a phone number that the user can dial from where they are - although we do
   * format in either 'national' or 'international' format depending on what the client asks for, we
   * do not currently support a more abbreviated format, such as for users in the same "area" who
   * could potentially dial the number without area code. Note that if the phone number has a
   * country calling code of 0 or an otherwise invalid country calling code, we cannot work out
   * which formatting rules to apply so we return the national significant number with no formatting
   * applied.
   *
   * @param number         the phone number to be formatted
   * @param numberFormat   the format the phone number should be formatted into
   * @return  the formatted phone number
   */
  String format(PhoneNumber number, PhoneNumberFormat numberFormat, {String defaultRegion: "US"}) {
    if (number != null && number.getNationalNumber == 0 && number.getRawInput != null) {
      // Unparseable numbers that kept their raw input just use that.
      // This is the only case where a number can be formatted as E164 without a
      // leading '+' symbol (but the original number wasn't parseable anyway).
      // TODO: Consider removing the 'if' above so that unparseable strings
      // without raw input format to the empty string instead of "+00"
      if (number.getRawInput.isNotEmpty) {
        return number.getRawInput;
      }
    }

    int countryCallingCode = number.getCountryCode;
    int nationalSignificantNumber = number.getNationalNumber;
    if (!_hasValidCountryCallingCode(countryCallingCode)) {
      return nationalSignificantNumber.toString();
    }

    // Note getRegionCodeForCountryCode() is used because formatting information
    // for regions which share a country calling code is contained by only one
    // region for performance reasons. For example, for NANPA regions it will be
    // contained in the metadata for US.
    String regionCode = getRegionCodeForCountryCode(countryCallingCode);

    // Metadata cannot be null because the country calling code is valid (which
    // means that the region code cannot be ZZ and must be one of our supported
    // region codes).
    PhoneMetadata metadata = _getMetadataForRegionOrCallingCode(countryCallingCode, regionCode);
    String formattedExtension = _maybeGetFormattedExtension(number, metadata, numberFormat);
    String formattedNationalNumber = _formatNsn(nationalSignificantNumber.toString(), metadata, numberFormat);
    return _prefixNumberWithCountryCallingCode(countryCallingCode, numberFormat, formattedNationalNumber, formattedExtension);
  }

  /**
   * A helper function that is used by format and formatByPattern.
   *
   * @param {number} countryCallingCode the country calling code.
   * @param {PhoneNumberFormat} numberFormat the format the
   *     phone number should be formatted into.
   * @param {string} formattedNationalNumber
   * @param {string} formattedExtension
   * @return {string} the formatted phone number.
   * @private
   */
  String _prefixNumberWithCountryCallingCode(
      int countryCallingCode, PhoneNumberFormat numberFormat, String formattedNationalNumber, String formattedExtension) {
    switch (numberFormat) {
      case PhoneNumberFormat.E164:
        return PLUS_SIGN + countryCallingCode.toString() + formattedNationalNumber + formattedExtension;
      case PhoneNumberFormat.INTERNATIONAL:
        return PLUS_SIGN + countryCallingCode.toString() + ' ' + formattedNationalNumber + formattedExtension;
      case PhoneNumberFormat.RFC3966:
        return _RFC3966_PREFIX + PLUS_SIGN + countryCallingCode.toString() + '-' + formattedNationalNumber + formattedExtension;
      case PhoneNumberFormat.NATIONAL:
      default:
        return formattedNationalNumber + formattedExtension;
    }
  }

  /**
   * Note in some regions, the national number can be written in two completely
   * different ways depending on whether it forms part of the NATIONAL format or
   * INTERNATIONAL format. The numberFormat parameter here is used to specify
   * which format to use for those cases. If a carrierCode is specified, this will
   * be inserted into the formatted string to replace $CC.
   *
   * @param {string} number a string of characters representing a phone number.
   * @param PhoneMetadata metadata the metadata for the
   *     region that we think this number is from.
   * @param {PhoneNumberFormat} numberFormat the format the
   *     phone number should be formatted into.
   * @param {string=} opt_carrierCode
   * @return {string} the formatted phone number.
   * @private
   */
  String _formatNsn(String number, PhoneMetadata metadata, PhoneNumberFormat numberFormat, {String opt_carrierCode}) {
    List<NumberFormat> intlNumberFormats = metadata.intlNumberFormat;
    // When the intlNumberFormats exists, we use that to format national number
    // for the INTERNATIONAL format instead of using the numberDesc.numberFormats.
    List<NumberFormat> availableFormats =
        (intlNumberFormats.isEmpty || numberFormat == PhoneNumberFormat.NATIONAL) ? metadata.numberFormat : metadata.intlNumberFormat;
    NumberFormat formattingPattern = _chooseFormattingPatternForNumber(availableFormats, number);
    return (formattingPattern == null) ? number : _formatNsnUsingPattern(number, formattingPattern, numberFormat, opt_carrierCode);
  }

  NumberFormat _chooseFormattingPatternForNumber(List<NumberFormat> availableFormats, String nationalNumber) {
    for (NumberFormat numFormat in availableFormats) {
      int size = numFormat.leadingDigitsPattern.length;
      if (size == 0 ||
          // We always use the last leading_digits_pattern, as it is the most
          // detailed.
          nationalNumber.startsWith(new RegExp(numFormat.leadingDigitsPattern[size - 1]))) {
        RegExp patternToMatch = new RegExp(numFormat.pattern);
        if (_matchesEntirely(patternToMatch, nationalNumber)) {
          return numFormat;
        }
      }
    }
    return null;
  }

  /**
   * Note that carrierCode is optional - if null or an empty string, no carrier
   * code replacement will take place.
   *
   * @param {string} nationalNumber a string of characters representing a phone
   *     number.
   * @param {NumberFormat} formattingPattern the formatting rule
   *     the phone number should be formatted into.
   * @param {PhoneNumberFormat} numberFormat the format the
   *     phone number should be formatted into.
   * @param {string=} opt_carrierCode
   * @return {string} the formatted phone number.
   * @private
   */
  String _formatNsnUsingPattern(
      String nationalNumber, NumberFormat formattingPattern, PhoneNumberFormat numberFormat, String opt_carrierCode) {
    String numberFormatRule = formattingPattern.format;
    RegExp patternToMatch = new RegExp(formattingPattern.pattern);
    String domesticCarrierCodeFormattingRule = formattingPattern.domesticCarrierCodeFormattingRule;
    String formattedNationalNumber = '';
    if (numberFormat == PhoneNumberFormat.NATIONAL &&
        opt_carrierCode != null &&
        opt_carrierCode.isNotEmpty &&
        domesticCarrierCodeFormattingRule.isNotEmpty) {
      // Replace the $CC in the formatting rule with the desired carrier code.
      String carrierCodeFormattingRule = domesticCarrierCodeFormattingRule.replaceAll(_CC_PATTERN, opt_carrierCode);
      // Now replace the $FG in the formatting rule with the first group and
      // the carrier code combined in the appropriate way.
      numberFormatRule = numberFormatRule.replaceAll(_FIRST_GROUP_PATTERN, carrierCodeFormattingRule);
      formattedNationalNumber = nationalNumber.replaceAllMapped(patternToMatch, (Match m) => numberFormatRule);
    } else {
      // Use the national prefix formatting rule instead.
      String nationalPrefixFormattingRule = formattingPattern.nationalPrefixFormattingRule;
      if (numberFormat == PhoneNumberFormat.NATIONAL && nationalPrefixFormattingRule != null && nationalPrefixFormattingRule.isNotEmpty) {
        String formattingRule = numberFormatRule.replaceFirst(_FIRST_GROUP_PATTERN, nationalPrefixFormattingRule);

        formattedNationalNumber = nationalNumber.replaceAllMapped(patternToMatch, (Match m) {
          String rule = formattingRule;
          for (int i = 1; i <= m.groupCount; i++) {
            rule = rule.replaceAll('\$$i', m.group(i));
          }
          return rule;
        });
      } else {
        formattedNationalNumber =
            nationalNumber.replaceAllMapped(patternToMatch, (Match m) => matchedGroupForReplacingString(m, numberFormatRule));
      }
    }
    if (numberFormat == PhoneNumberFormat.RFC3966) {
      // Strip any leading punctuation.
      formattedNationalNumber = formattedNationalNumber.replaceAll(new RegExp('^' + _SEPARATOR_PATTERN), '');
      // Replace the rest with a dash between each number group.
      formattedNationalNumber = formattedNationalNumber.replaceAll(new RegExp(_SEPARATOR_PATTERN), '-');
    }
    return formattedNationalNumber;
  }

  /**
   * This method will replace the $1,$2,$3.. with appropriate matched groups.
   * Use case: This method is meant as an alternative for Javascript's String.replace(regex,regex)
   */
  String matchedGroupForReplacingString(Match m, String numberFormatRule) {
    String rule = numberFormatRule;
    for (int i = 1; i <= m.groupCount; i++) {
      rule = rule.replaceAll('\$$i', m.group(i));
    }
    return rule;
  }

  /**
   * Gets the formatted extension of a phone number, if the phone number had an
   * extension specified. If not, it returns an empty string.
   *
   * @param {PhoneNumber} number the PhoneNumber that might have
   *     an extension.
   * @param {PhoneMetadata} metadata the metadata for the
   *     region that we think this number is from.
   * @param {PhoneNumberFormat} numberFormat the format the
   *     phone number should be formatted into.
   * @return {string} the formatted extension if any.
   * @private
   */
  String _maybeGetFormattedExtension(PhoneNumber number, PhoneMetadata metadata, PhoneNumberFormat numberFormat) {
    if (!(number.getExtension != null) || number.getExtension.isEmpty) {
      return '';
    } else {
      if (numberFormat == PhoneNumberFormat.RFC3966) {
        return _RFC3966_EXTN_PREFIX + number.getExtension;
      } else {
        //TODO: ADD preferred extn once Metadata integration is done. US does not have preferred extn.
        if (metadata.preferredExtnPrefix != null) {
          return metadata.preferredExtnPrefix + number.getExtension;
        } else {
          return _DEFAULT_EXTN_PREFIX + number.getExtension;
        }
      }
    }
  }

  bool _hasValidCountryCallingCode(int countryCallingCode) {
    return DefaultPhoneRegionData.countryCodeToRegionCodeMap.containsKey(countryCallingCode);
  }

  String getRegionCodeForCountryCode(int countryCallingCode) {
    List<String> regionCodes = DefaultPhoneRegionData.countryCodeToRegionCodeMap[countryCallingCode];
    return regionCodes == null ? _UNKNOWN_REGION : regionCodes[0];
  }

  /**
   * @param {number} countryCallingCode
   * @param {?string} regionCode
   * @return {PhoneMetadata}
   * @private
   */
  PhoneMetadata _getMetadataForRegionOrCallingCode(int countryCallingCode, String regionCode) {
    return REGION_CODE_FOR_NON_GEO_ENTITY == regionCode
        ? getMetadataForNonGeographicalRegion(countryCallingCode)
        : getMetadataForRegion(regionCode);
  }

  /**
   * @param {number} countryCallingCode
   * @return {PhoneMetadata}
   */
  PhoneMetadata getMetadataForNonGeographicalRegion(int countryCallingCode) {
    return getMetadataForRegion(countryCallingCode.toString());
  }

  /**
   * Returns the metadata for the given region code or {@code null} if the region
   * code is invalid or unknown.
   *
   * @param {?string} regionCode
   * @return {PhoneMetadata}
   */
  PhoneMetadata getMetadataForRegion(String regionCode) {
    if (regionCode == null) {
      return null;
    }
    regionCode = regionCode.toUpperCase();
    PhoneMetadata metadata = regionToMetadataMap[regionCode];
    if (metadata == null) {
      PhoneMetadata metadata = metaDataFromJSON.getRegionData(regionCode);
      regionToMetadataMap[regionCode] = metadata; //phone meta data
      return metadata;
    }
    return metadata;
  }

  /**
   * Normalizes a string of characters representing a phone number. This is a
   * wrapper for normalize(String number) but does in-place normalization of the
   * StringBuffer provided.
   *
   * @param {!String} number a String representing a phone number that will be normalized in place.
   * @private
   */
  String _normalizeSB(String number) {
    String normalizedNumber = normalize(number);
    return normalizedNumber;
  }

  /**
   * Normalizes a string of characters representing a phone number. This performs
   * the following conversions:
   *   Punctuation is stripped.
   *   For ALPHA/VANITY numbers:
   *   Letters are converted to their numeric representation on a telephone
   *       keypad. The keypad used here is the one defined in ITU Recommendation
   *       E.161. This is only done if there are 3 or more letters in the number,
   *       to lessen the risk that such letters are typos.
   *   For other numbers:
   *   Wide-ascii digits are converted to normal ASCII (European) digits.
   *   Arabic-Indic numerals are converted to European numerals.
   *   Spurious alpha characters are stripped.
   *
   * @param {string} number a string of characters representing a phone number.
   * @return {string} the normalized string version of the phone number.
   */
  String normalize(String number) {
    if (_matchesEntirely(_VALID_ALPHA_PHONE_PATTERN, number)) {
      return _normalizeHelper(number, _ALL_NORMALIZATION_MAPPINGS, true);
    } else {
      return normalizeDigitsOnly(number);
    }
  }

  String normalizeDigitsOnly(String number) {
    return _normalizeHelper(number, DIGIT_MAPPINGS, true);
  }

  /**
   * Normalizes a string of characters representing a phone number by replacing
   * all characters found in the accompanying map with the values therein, and
   * stripping all other characters if removeNonMatches is true.
   *
   * @param {string} number a string of characters representing a phone number.
   * @param {!Map.<string, string>} normalizationReplacements a mapping of
   *     characters to what they should be replaced by in the normalized version
   *     of the phone number.
   * @param {boolean} removeNonMatches indicates whether characters that are not
   *     able to be replaced should be stripped from the number. If this is false,
   *     they will be left unchanged in the number.
   * @return {string} the normalized string version of the phone number.
   * @private
   */
  String _normalizeHelper(String number, Map<String, Object> normalizationReplacements, bool removeNonMatches) {
    String normalizedNumber = "";
    String character;
    String newDigit;
    int numberLength = number.length;
    for (int i = 0; i < numberLength; ++i) {
      character = number[i];
      newDigit = normalizationReplacements[character.toUpperCase()];
      if (newDigit != null) {
        //appending
        normalizedNumber += (newDigit);
      } else if (!removeNonMatches) {
        //appending
        normalizedNumber += (character);
      }
      // If neither of the above are true, we remove this character.
    }
    return normalizedNumber;
  }

  /**
   * Check whether the entire input sequence can be matched against the regular
   * expression.
   *
   * @param {!RegExp|string} regex the regular expression to match against.
   * @param {string} str the string to test.
   * @return {boolean} true if str can be matched entirely against regex.
   * @private
   */
  bool _matchesEntirely(RegExp regex, String str) {
    Match matchedGroups = regex.matchAsPrefix(str);
    if (matchedGroups != null && matchedGroups[0].length == str.length) {
      return true;
    }
    return false;
  }
}

class NumberParseException implements Exception {
  ErrorType errorType;
  String message;

  NumberParseException(ErrorType errorType, String message) {
    this.message = message;
    this.errorType = errorType;
  }

  String toString() => "Error type: $errorType. $message";
}
