export const meta={name:'Quarterback swap',desc:'A laced football winds back, spirals across a short passing lane and settles after the catch.',tags:['ui','football','swap'],size:[80,32],origin:[40,20],duration:.7,loop:false,fps:30,bg:'light',options:{variant:'arc',seed:1}};
const colors={d:0xff2d5314,r:0xff1a3d9f,h:0xff4073cb,s:0xff192b6b,c:0xffcee9f2};
const ball=['........ddddddd........','.....dddrrrrrrrddd.....','...ddrrrhhhhhhrrrrdd...','..drrcrhhhhhhrrrrcrrd..','.drrrcrrrrrrrrrrrcrrrd.','drrrrcrrcccccccrrcrrrrd','drrrrcrrrcrcrcrrrcrrrrd','.drrrcrrrrrrrrrrrcrrrd.','..drrcrsssssssssscrrd..','...ddrrsssssssssrrdd...','.....dddsssssssddd.....','........ddddddd........'];
export function draw(p,t,o){
 if(t>=meta.duration)return;
 const u=Math.min(1,t/.12),flight=Math.min(1,Math.max(0,(t-.12)/.32));
 let x=t<.12?-12*u*u:t<.44?-12+30*flight:t<.49?18:18*Math.max(0,1-(t-.49)/.17);
 let y=t<.12?0:t<.44?-(o.variant==='dart'?2:5)*Math.sin(Math.PI*flight):t<.56?-Math.sin((t-.44)*Math.PI/.12)*2:0;
 if(o.variant==='spiral'&&t>.12&&t<.44)y+=Math.sin(flight*Math.PI*6)*1.5;
 if(t>.15&&t<.43){p.line(x-21,y-2,x-15,y-2,colors.d,.6);p.line(x-18,y+3,x-14,y+3,colors.r,.7);}
 const pose=t>.12&&t<.44&&Math.floor(t*30)%4<2?ball.map((row,i)=>i===5?row.replace('ccccccc','rrrrrrr'):i===6?row.replace('crcrcr','hhhhhh'):row):ball;
 p.sprite(pose,colors,Math.round(x)-11,Math.round(y)-6);
 if(t>.44&&t<.51){const k=(t-.44)/.07;p.line(18+15+k*3,-5,18+17+k*4,-7,colors.d,1-k);p.line(18+15+k*3,4,18+17+k*4,6,colors.r,1-k);}
}
