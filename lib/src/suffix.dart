
/// An enumeration representing different suffixes that can be appended to a string.
/// 
/// The available suffixes are:
/// 
/// - `cr`: Carriage return (`\r`)
/// - `crlf`: Carriage return + Line feed (`\r\n`)
/// - `tab`: Tab (`\t`)
/// - `none`: No suffix (`''`)
/// 
/// Each suffix is associated with its corresponding string value.
enum Suffix {
  cr('\r'), // Carriage return
  crlf('\r\n'), // Carriage return + Line feed
  tab('\t'), // Tab
  none(''); // No suffix

  final String value;

  const Suffix(this.value);
}
