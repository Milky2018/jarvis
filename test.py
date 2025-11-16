def fibonacci(n):
    """
    计算斐波那契数列的第n个数
    
    参数:
        n: 要计算的斐波那契数列位置（从0开始）
    
    返回:
        第n个斐波那契数
    """
    if n < 0:
        raise ValueError("n must be non-negative")
    elif n == 0:
        return 0
    elif n == 1:
        return 1
    else:
        return fibonacci(n - 1) + fibonacci(n - 2)


def fibonacci_iterative(n):
    """
    使用迭代方法计算斐波那契数列的第n个数（更高效）
    
    参数:
        n: 要计算的斐波那契数列位置（从0开始）
    
    返回:
        第n个斐波那契数
    """
    if n < 0:
        raise ValueError("n must be non-negative")
    elif n == 0:
        return 0
    elif n == 1:
        return 1
    
    prev, curr = 0, 1
    for _ in range(2, n + 1):
        prev, curr = curr, prev + curr
    return curr


def fibonacci_sequence(n):
    """
    生成前n个斐波那契数列
    
    参数:
        n: 要生成的斐波那契数列长度
    
    返回:
        包含前n个斐波那契数的列表
    """
    if n <= 0:
        return []
    elif n == 1:
        return [0]
    
    sequence = [0, 1]
    for i in range(2, n):
        sequence.append(sequence[i - 1] + sequence[i - 2])
    return sequence


# 测试代码
if __name__ == "__main__":
    print("斐波那契数列测试：")
    print("-" * 40)
    
    # 测试单个斐波那契数
    test_n = 10
    print(f"fibonacci({test_n}) = {fibonacci(test_n)}")
    print(f"fibonacci_iterative({test_n}) = {fibonacci_iterative(test_n)}")
    
    print()
    
    # 测试斐波那契数列
    print(f"前15个斐波那契数：")
    print(fibonacci_sequence(15))
    
    print()
    
    # 性能比较
    print("前10个斐波那契数（递归方法）：")
    for i in range(10):
        print(f"F({i}) = {fibonacci(i)}")
