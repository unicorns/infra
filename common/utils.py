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
