enum CountryCodeSource { FROM_NUMBER_WITH_PLUS_SIGN, FROM_NUMBER_WITH_IDD, FROM_NUMBER_WITHOUT_PLUS_SIGN, FROM_DEFAULT_COUNTRY }

class PhoneNumber {
  /**
   * Definition of the class representing international telephone numbers. This class is hand-created
   * based on the class file compiled from phonenumber.proto. Please refer to that file for detailed
   * descriptions of the meaning of each field.
   */

  bool _italianLeadingZero = false;
  bool get getItalianLeadingZero => _italianLeadingZero;
  void set setItalianLeadingZero(bool value) {
    _italianLeadingZero = value;
  }

  int _numberOfLeadingZeros = 0;
  int get getNumberOfLeadingZeros => _numberOfLeadingZeros;
  void set setNumberOfLeadingZeros(int value) {
    _numberOfLeadingZeros = value;
  }

  String _extension = "";
  String get getExtension => _extension;
  void set setExtension(String value) {
    _extension = value;
  }

  int _countryCode = 0;
  int get getCountryCode => _countryCode;
  void set setCountryCode(int value) {
    _countryCode = value;
  }

  int _nationalnumber = 0;
  int get getNationalNumber => _nationalnumber;
  void set setNationalNumber(int value) {
    _nationalnumber = value;
  }

  String _rawInput = "";
  String get getRawInput => _rawInput;
  void set setRawInput(String value) {
    _rawInput = value;
  }

  String _preferredDomesticCarrierCode = "";
  String get getPreferredDomesticCarrierCode => _preferredDomesticCarrierCode;
  void set setPreferredDomesticCarrierCode(String value) {
    _preferredDomesticCarrierCode = value;
  }

  CountryCodeSource _countryCodeSource;
  CountryCodeSource get getCountryCodeSource => _countryCodeSource;
  void set setCountryCodeSource(CountryCodeSource value) {
    _countryCodeSource = value;
  }

  PhoneNumber() {
    _countryCodeSource = CountryCodeSource.FROM_NUMBER_WITH_PLUS_SIGN;
  }

  bool hasRawInput() {
    return _rawInput != null && _rawInput != '';
  }

  bool hasCountryCodeSource() {
    return this._countryCodeSource != null;
  }

  String toString() {
    String result = "";
    for (int i = 0; i < _numberOfLeadingZeros; i++) {
      result += '0';
    }
    result += "$_countryCode$_nationalnumber$_extension";
    return result;
  }
}
