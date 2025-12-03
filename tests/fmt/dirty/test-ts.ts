interface User{name:string;age:number;email?:string}
type Status='active'|'inactive'|'pending';
type UserWithStatus=User&{status:Status};
const greet=(user:User):string=>{return `Hello, ${user.name}!`}
async function fetchUser<T extends User>(id:number):Promise<T|null>{return null}
class Repository<T>{private items:T[]=[];add(item:T):void{this.items.push(item)}getAll():readonly T[]{return this.items}}
const processUsers=<T extends User>(users:T[],fn:(u:T)=>void):void=>{users.forEach(fn)}
type PartialUser=Partial<User>;type RequiredUser=Required<User>;type ReadonlyUser=Readonly<User>;
const userMap=new Map<string,User>();const userSet=new Set<number>();
const assertUser=(value:unknown):value is User=>{return typeof value==='object'&&value!==null&&'name' in value}