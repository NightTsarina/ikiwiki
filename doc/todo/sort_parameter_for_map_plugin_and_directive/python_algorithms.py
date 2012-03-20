testdata = "c/3 a b d b/1 c/1 c/2/x c/2 c".split(" ")

def strategy_byearlychild(sequence):
    """Sort by earliest child

    When this strategy is used, a parent is displayed with all its children as
    soon as the first child is supposed to be shown.

    >>> strategy_byearlychild(testdata)
    ['c', 'c/3', 'c/1', 'c/2', 'c/2/x', 'a', 'b', 'b/1', 'd']
    """

    # first step: pull parents to top
    def firstchildindex(item):
        childindices = [i for (i,text) in enumerate(sequence) if text.startswith(item + "/")]
        # distinction required as min(foo, *[]) tries to iterate over foo
        if childindices:
            return min(sequence.index(item), *childindices)
        else:
            return sequence.index(item)
    sequence = sorted(sequence, key=firstchildindex)

    # second step: pull other children to the start too
    return strategy_byparents(sequence)

def strategy_byparents(sequence):
    """Sort by parents only

    With this strategy, children are sorted *under* their parents regardless of
    their own position, and the parents' positions are determined only by
    comparing the parents themselves.

    >>> strategy_byparents(testdata)
    ['a', 'b', 'b/1', 'd', 'c', 'c/3', 'c/1', 'c/2', 'c/2/x']
    """

    def partindices(item):
        """Convert an entry a tuple of the indices of the entry's parts.

        >>> sequence = testsequence
        >>> assert partindices("c/2/x") == (sequence.index("c"), sequence.index("c/2"), sequence.index("c/2/x"))
        fnord
        """
        return tuple(sequence.index(item.rsplit('/', i)[0]) for i in range(item.count('/'), -1, -1))

    return sorted(sequence, key=partindices)

def strategy_forcedsequence(sequence):
    """Forced Sequence Mode

    Using this strategy, all entries will be shown in the sequence; this can
    cause parents to show up multiple times.

    The only reason why this is not the identical function is that parents that
    are sorted between their children are bubbled up to the top of their
    contiguous children to avoid being repeated in the output.

    >>> strategy_forcedsequence(testdata)
    ['c/3', 'a', 'b', 'd', 'b/1', 'c', 'c/1', 'c/2', 'c/2/x']
    """

    # this is a classical bubblesort. other algorithms wouldn't work because
    # they'd compare non-adjacent entries and move the parents before remote
    # children. python's timsort seems to work too...

    for i in range(len(sequence), 1, -1):
        for j in range(1, i):
            if sequence[j-1].startswith(sequence[j] + '/'):
                sequence[j-1:j+1] = [sequence[j], sequence[j-1]]

    return sequence

def strategy_forcedsequence_timsort(sequence):
    sequence.sort(lambda x,y: -1 if y.startswith(x) else 1)
    return sequence

if __name__ == "__main__":
    import doctest
    doctest.testmod()

    import itertools

    for perm in itertools.permutations(testdata):
        if strategy_forcedsequence(testdata[:]) != strategy_forcedsequence_timsort(testdata[:]):
            print "difference for testdata", testdata
            print "normal", strategy_forcedsequence(testdata[:])
            print "timsort", strategy_forcedsequence_timsort(testdata[:])
