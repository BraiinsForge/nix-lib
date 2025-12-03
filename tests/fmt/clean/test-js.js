const foo = { bar: 'baz', qux: 123, nested: { a: 1, b: 2, c: 3 } };
const arr = [1, 2, 3, 4, 5, { x: 10, y: 20 }];
function hello(name) {
    return `Hello, ${name}!`;
}
const greet = async user => {
    const { name, age } = user;
    return { greeting: `Hi ${name}`, isAdult: age >= 18 };
};
class Person {
    constructor(name, age) {
        this.name = name;
        this.age = age;
    }
    greet() {
        return `I'm ${this.name}`;
    }
}
const merged = { ...foo, ...{ extra: 'value' } };
const value = foo?.nested?.missing ?? 'default';
const nums = [1, 2, 3].map(n => n * 2).filter(n => n > 2);
const longString =
    'This is a very long string that should probably be kept on one line but demonstrates string handling';
