from json import JSONDecoder


def deep_equal(obj1, obj2):
    """
    Deep compare two objects. Return True if they are equal, False otherwise.
    """
    if type(obj1) != type(obj2):
        return False
    if type(obj1) == dict:
        if len(obj1) != len(obj2):
            return False
        for key in obj1:
            if key not in obj2:
                return False
            if not deep_equal(obj1[key], obj2[key]):
                return False
        return True
    if type(obj1) == list:
        if len(obj1) != len(obj2):
            return False
        for i in range(len(obj1)):
            if not deep_equal(obj1[i], obj2[i]):
                return False
        return True
    return obj1 == obj2


def extract_json_objects(text, decoder=JSONDecoder()):
    """
    Find JSON objects in text, and yield the decoded JSON data

    Does not attempt to look for JSON arrays, text, or other JSON types outside
    of a parent JSON object.

    Derived from https://stackoverflow.com/a/54235803

    This is useful for handling JSON objects embedded in a string, such as
    when this bug pollutes the output:
    https://github.com/hashicorp/terraform/issues/35159
    """
    pos = 0
    while True:
        match = text.find("{", pos)
        if match == -1:
            break
        try:
            result, index = decoder.raw_decode(text[match:])
            yield result
            pos = match + index
        except ValueError:
            pos = match + 1
