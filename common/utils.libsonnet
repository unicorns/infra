{
  slugify(s)::
    // Convert string to lowercase
    local lowercase = std.asciiLower(s);

    // Convert string to array of characters
    local chars = std.stringChars(lowercase);

    // Define allowed characters (alphanumeric and space)
    local isAllowed = function(c) (
      (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'z') ||
      c == ' '
    );

    // Filter only allowed characters
    local filteredChars = std.filter(isAllowed, chars);

    // Replace spaces with dashes
    local replaceSpaces = std.map(
      function(c) if c == ' ' then '-' else c,
      filteredChars
    );

    // Join characters back into a string
    std.join('', replaceSpaces),
}
