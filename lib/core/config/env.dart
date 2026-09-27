/// Supabase connection settings.
///
/// The publishable ("anon") key is safe to ship inside the app — access is
/// protected by Row Level Security on the server. Never place the `secret` key
/// here.
class Env {
  Env._();

  static const supabaseUrl = 'https://iyjgpzicdftkwwibtdzz.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_Zv70R7vdfUUeiSgDWB1bSA__a8vdduW';
}
