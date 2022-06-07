
def pi(digits):
    i = 0
    k = 0
    k1 = 1
    n=1
    a=0
    d=1
    t=0
    u=0
    while 1:
        k = k + 1
        t = n + n
        n = n * k
        a = a + t
        k1 = k1 + 2
        a = a * k1
        d = d * k1
        if a >= n:
            v = n*3+a
            t = v//d
            u = v%d
            u = u + n
            if d > u:
                print(t % 10, end='')
                if (i == 0):
                    print('.', end='')
                i = i + 1
                if i % 80 == 79:
                    print()
                if i >= digits:
                    print()
                    return 0
                a = a - d*t
                a = a * 10
                n = n * 10

pi(10000)
