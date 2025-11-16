def fibonacci(n: int) -> int:
    """
    Calculate the nth Fibonacci number
    
    Args:
        n: The position in the Fibonacci sequence (starting from 0)
    
    Returns:
        The nth Fibonacci number
    """
    if n < 0:
        raise ValueError("n must be non-negative")
    elif n == 0:
        return 0
    elif n == 1:
        return 1
    else:
        return fibonacci(n - 1) + fibonacci(n - 2)


def fibonacci_iterative(n: int) -> int:
    """
    Calculate the nth Fibonacci number using iterative method (more efficient)
    
    Args:
        n: The position in the Fibonacci sequence (starting from 0)
    
    Returns:
        The nth Fibonacci number
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


def fibonacci_sequence(n: int) -> list[int]:
    """
    Generate the first n Fibonacci numbers
    
    Args:
        n: The length of the Fibonacci sequence to generate
    
    Returns:
        A list containing the first n Fibonacci numbers
    """
    if n <= 0:
        return []
    elif n == 1:
        return [0]
    
    sequence = [0, 1]
    for i in range(2, n):
        sequence.append(sequence[i - 1] + sequence[i - 2])
    return sequence


def main() -> None:
    """
    Main function to test Fibonacci functions
    """
    print("Fibonacci Sequence Test:")
    print("-" * 40)
    
    # Test individual Fibonacci number
    test_n: int = 10
    print(f"fibonacci({test_n}) = {fibonacci(test_n)}")
    print(f"fibonacci_iterative({test_n}) = {fibonacci_iterative(test_n)}")
    
    print()
    
    # Test Fibonacci sequence
    print(f"First 15 Fibonacci numbers:")
    print(fibonacci_sequence(15))
    
    print()
    
    # Performance comparison
    print("First 10 Fibonacci numbers (recursive method):")
    for i in range(10):
        print(f"F({i}) = {fibonacci(i)}")


if __name__ == "__main__":
    main()
