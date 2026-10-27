// 운영 요청 없이 실제 브리지를 모의 실행한다. 선택적 첫 인자로 비교할 이전 JS 경로를 받을 수 있다.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { run, fixture, response, balance } from '../Tests/BridgeTests/harness.mjs';
const source = process.argv[2] ? await readFile(process.argv[2], 'utf8') : undefined;

const base=1700000000000;
// 정해진 시각을 기준으로 가상의 서버 작업을 만든다.
const record=(id,status='succeeded',offset=-120000)=>({...fixture(id),status,created_at:new Date(base+offset).toISOString()});
// 서버 작업을 브리지가 보관하는 최소 필드로 변환한다.
const prior=r=>({id:r.request_id,model:r.model_name,mediaType:r.media_type,status:r.status,createdAt:r.created_at});
// 초기 연결 비용을 제외한 정상 상태의 잔액·작업 캐시를 만든다.
const seed=jobs=>({balance:{total:'100.25',reserved:'10.10',available:'90.15'},balanceFetchedAt:base,jobs:jobs.map(prior),balanceRefreshUntil:0});
// 5초 주기의 가상 시계를 진행하며 목록·개별 작업·잔액 조회 횟수를 각각 센다.
async function probe(label,rows,initial,offsets,activeIDs=[]){
 let state=initial, last=base, log=[], bridgeCache;
 for (const offset of offsets){
  let terminalCount=0;
  const previousJobs=(state?.jobs??[]).filter(job=>!['succeeded','failed','cancelled'].includes(job.status)||++terminalCount<=50);
  const result=await run({source,bridgeCache,now:base+offset,since:state?last:0,previousWorkspaceKey:state?'fixture-user:personal':'',previousJobs,previousBalance:state?.balance??null,previousBalanceFetchedAt:state?.balanceFetchedAt??0,balanceRefreshUntil:state?.balanceRefreshUntil??0,activeIDs,fetch:async url=>{
   if(url.endsWith('/balance'))return response(balance);
   if(url.includes('/requests/'))return response(record(url.split('/').pop(),'running_provider'));
   const u=new URL(url,'https://fixture.invalid'),limit=Number(u.searchParams.get('limit')),start=Number(u.searchParams.get('cursor')??0);
   return response({items:rows.slice(start,start+limit),next_cursor:start+limit<rows.length?String(start+limit):null});
  }});
  assert.ok(!result.data.error,result.json);
  log.push({seconds:offset/1000,jobs:result.calls.filter(c=>c.url.includes('/requests')).length,credits:result.calls.filter(c=>c.url.endsWith('/balance')).length});
  state=result.data;bridgeCache=result.bridgeCache;last=base+offset;
 }
 return {label,cycles:log.length,job_reads:log.reduce((n,x)=>n+x.jobs,0),credit_reads:log.reduce((n,x)=>n+x.credits,0),...(log.length<10?{cycles_detail:log}:{} )};
}
// 정상 1시간, 초기 대량 이력, 오래된 미완료 작업, 50개 초과 종료 이력을 비교한다.
const reports=[];
const steady=[record('stable')];
reports.push(await probe('steady one hour, excludes startup',steady,seed(steady),Array.from({length:720},(_,i)=>(i+1)*5000)));
reports.push(await probe('first launch with more than 1000 historical records',Array.from({length:1001},(_,i)=>record('history-'+i,'succeeded',-120000-i*1000)),null,[0]));
const history=Array.from({length:20},(_,i)=>record('recent-'+i));
const old=Array.from({length:3},(_,i)=>record('active-'+i,'running_provider',-600000));
reports.push(await probe('three known active jobs outside latest page',history,seed([...history,...old]),[5000],old.map(x=>x.request_id)));
const burst=Array.from({length:80},(_,i)=>record('burst-'+i,'succeeded',i<60?20000-i*300:-120000-i*1000));
reports.push(await probe('unchanged burst history exceeding 50 retained terminal records',burst,seed(burst.slice(0,50)),[30000,35000,40000,45000,50000,55000]));
console.log(JSON.stringify(reports,null,2));
