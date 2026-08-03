{
  slugify(s)::
    local lowercase = std.asciiLower(s);
    local chars = std.stringChars(lowercase);
    local isAllowed = function(c) (
      (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'z') ||
      c == '-' ||
      c == ' '
    );
    local filteredChars = std.filter(isAllowed, chars);
    local replaceSpaces = std.map(
      function(c) if c == ' ' then '-' else c,
      filteredChars
    );
    std.join('', replaceSpaces),
}
