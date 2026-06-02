fib = [0,1]

for i in range(1,100):
    new_fib = fib[i] + fib[i-1]
    fib.append(new_fib)

fib_hex = list(map(lambda x: hex(x), fib))

print( dec(001b208e0))
print( hex(00097c81))
# def decToHex(num):
#     hex = hex(num)