# Démo Phase 1

## Prérequis
- Supabase local tourne (`supabase start`)
- Edge Functions servent (`supabase functions serve`)
- Back office tourne (`flutter run -d chrome ...`)

## Scénario de démo

1. **Login admin**
   - Saisir `admin@local.test` / `AdminPass123!`
   - Cliquer "Se connecter" → redirection `/establishments`

2. **CRUD Établissements**
   - Voir "Lounge Plateau" (seed)
   - Cliquer "Nouvel établissement" → saisir "Resto Centre-ville" + fuseau "Africa/Yaounde" → Enregistrer
   - La liste affiche 2 lignes
   - Cliquer sur "Resto Centre-ville" → modifier le fuseau → Enregistrer → vérifier dans la liste
   - Supprimer "Resto Centre-ville" → confirmer → disparition

3. **Création Gérant**
   - Aller dans "Gérants" → voir "Dev Manager" (seed)
   - Cliquer "Nouveau gérant" → saisir "Jean Dupont" / jean@local.test / Test1234! → cocher "Lounge Plateau" → Créer
   - Retour à la liste : "Jean Dupont" apparaît avec "1 établissement(s)"

4. **Test isolation gérant (via Studio)**
   - Se déconnecter
   - Se connecter avec `jean@local.test` / `Test1234!`
   - Dans Studio (`http://127.0.0.1:54323`), exécuter en SQL `select * from establishments` en tant que `jean@local.test` → doit retourner uniquement "Lounge Plateau" (preuve que RLS fonctionne)

## Résultat attendu

Tous les points ci-dessus marchent, l'UI est navigable, les données persistent après refresh.
Les tests `flutter test` et `supabase test db` passent tous.
