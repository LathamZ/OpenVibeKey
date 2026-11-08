import unittest, math
from wechat_session_projection import recent_projection
scope='a'*64
class ProjectionTests(unittest.TestCase):
 def project(self,rows,**kw):return recent_projection(rows,account_scope=kw.get('scope',scope),generated_at=2000,native_root_verified=kw.get('verified',True))
 def row(self,i,**kw):return dict(username=f'fixture-{i}',nick_name=f'Fixture {i}',last_timestamp=1000+i,is_hidden=0,**kw)
 def test_limit_order(self):
  r=self.project([self.row(i) for i in range(70)])['sessions'];self.assertEqual(len(r),50);self.assertEqual(r[0]['last_activity'],1069);self.assertEqual(r[-1]['last_activity'],1020)
 def test_hidden(self):
  a=self.row(1);a['is_hidden']=1;self.assertEqual(self.project([a])['sessions'],[])
 def test_missing_hidden(self):
  a=self.row(1);del a['is_hidden']
  with self.assertRaises(ValueError):self.project([a])
 def test_scope(self):
  a=self.row(1);self.assertNotEqual(self.project([a])['sessions'][0]['id'],self.project([a],scope='b'*64)['sessions'][0]['id'])
 def test_identity(self):
  a=self.row(1);b=dict(a,nick_name='Renamed',last_timestamp=1500);r=self.project([a,b])['sessions'];self.assertEqual(len(r),1);self.assertEqual(r[0]['id'],self.project([a])['sessions'][0]['id']);self.assertEqual(r[0]['last_activity'],1500)
 def test_pinned(self):
  a=self.row(1,sort_timestamp=9999999999);b=self.row(2);self.assertEqual(self.project([a,b])['sessions'][0]['title'],b['nick_name'])
 def test_invalid(self):
  self.assertEqual(self.project([dict(self.row(i),last_timestamp=x) for i,x in enumerate([0,-1,float('nan'),float('inf'),9999])])['sessions'],[])
 def test_milliseconds(self):
  r=recent_projection([dict(self.row(0),last_timestamp=1700000000000)],account_scope=scope,generated_at=1700000010,native_root_verified=True)
  self.assertEqual(r['sessions'][0]['last_activity'],1700000000)
 def test_empty(self):self.assertEqual(self.project([])['sessions'],[])
 def test_unverified(self):
  with self.assertRaises(ValueError):self.project([],verified=False)
 def test_bad_scope(self):
  with self.assertRaises(ValueError):self.project([],scope='wrong')
if __name__ == '__main__': unittest.main()
