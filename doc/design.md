def fun()
	print("hello world")
end

func fun()
{
	print("hello world");
}

DEFINE_FUN fun 2
PUSH "hello world"
CALL print, 1

func fun()
{
	var a = 12;
	var b;
	b = 14;
	print(a + b);
}

DEFINE_FUN fun
> PUSH_UINT32 12
> LOCAL_VARIABLE a Integer <InitialValue> [1]
> LOCAL_VARIABLE b Any?
> PUSH_UINT32 14
> SET_LOCAL b
> PUSH_LOCAL a
> PUSH_LOCAL b
> CALL + 2
> CALL print
