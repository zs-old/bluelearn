import { Hono } from 'hono'
import { zValidator } from '@hono/zod-validator'
import { createTopicSchema } from '@bluelearn/schemas'
import { requireUser } from '../middleware/auth.middleware'
import { slugify } from '../lib/slug'
import type { HonoEnv } from '../types'

// A topic's title/summary/body live on the canonical guide's current
// revision, not on the base. These embeds walk guide_bases -> canonical
// guide -> its live revision.
const CANONICAL_SUMMARY = `
  canonical:guides!guide_bases_canonical_guide_id_fkey(
    current:guide_revisions!guides_current_revision_id_fkey(
      summary
    )
  )
`

const CANONICAL_CONTENT = `
  canonical:guides!guide_bases_canonical_guide_id_fkey(
    id,
    slug,
    current:guide_revisions!guides_current_revision_id_fkey(
      id,
      title,
      summary,
      body,
      created_at
    )
  )
`

// Blank summary/body collapse to NULL to match the create_topic RPC defaults
const createTopicBody = createTopicSchema.extend({
  summary: createTopicSchema.shape.summary.transform((v) => v || null),
  body: createTopicSchema.shape.body.transform((v) => v || null),
})

export const guidesRouter = new Hono<HonoEnv>()
  // List published topics, alphabetical. RLS hides drafts from non-authors.
  .get('/', async (c) => {
    const supabase = c.get('supabase')
    const { data, error } = await supabase
      .from('guide_bases')
      .select(`id, slug, title, knowledge_type, ${CANONICAL_SUMMARY}`)
      .eq('status', 'published')
      .order('title')

    if (error) return c.json({ error: error.message }, 500)

    const topics = (data ?? []).map(({ canonical, ...base }) => ({
      ...base,
      summary: canonical?.current?.summary ?? null,
    }))
    return c.json({ topics })
  })

  // Create a topic: bundles the guide_base + first guide + draft revision in one
  // transaction via the create_topic RPC (RLS still applies, SECURITY INVOKER).
  .post('/', requireUser, zValidator('json', createTopicBody), async (c) => {
    const supabase = c.get('supabase')
    const { title, knowledge_type, summary, body } = c.req.valid('json')

    const slug = slugify(title)
    if (!slug) {
      return c.json({ error: 'Title must contain at least one letter or number' }, 400)
    }

    const { data: revision_id, error } = await supabase.rpc('create_topic', {
      p_title: title,
      p_slug: slug,
      p_knowledge_type: knowledge_type,
      p_summary: summary ?? undefined,
      p_body: body ?? undefined,
    })

    if (error) {
      if (error.code === '23505') {
        return c.json({ error: 'A topic with this title already exists' }, 409)
      }
      return c.json({ error: error.message }, 500)
    }

    // create_topic returns the draft revision id in order for the client
    // to route to its editor
    return c.json({ revision_id, slug }, 201)
  })

  // Resolve a topic by slug to its canonical content + subject tags. The prereq/
  // dependent neighborhood is deferred to the graph pass.
  .get('/:slug', async (c) => {
    const supabase = c.get('supabase')
    const slug = c.req.param('slug').toLowerCase()

    const { data: topic, error } = await supabase
      .from('guide_bases')
      .select(`id, slug, title, knowledge_type, status, created_at, updated_at, ${CANONICAL_CONTENT}`)
      .eq('slug', slug)
      .maybeSingle()

    if (error) return c.json({ error: error.message }, 500)
    if (!topic) return c.json({ error: 'Topic not found' }, 404)

    const { data: tagRows, error: tagError } = await supabase
      .from('guide_subjects')
      .select('subjects(id, slug, name)')
      .eq('guide_base_id', topic.id)

    if (tagError) return c.json({ error: tagError.message }, 500)
    const subjects = (tagRows ?? []).map((r) => r.subjects).filter((s) => s !== null)

    return c.json({ topic, subjects })
  })

  // Archive the topic. Per RLS this is moderator/admin-only (authors cannot move
  // a topic off 'draft'); a non-permitted caller simply matches zero rows.
  .delete('/:slug', requireUser, async (c) => {
    const supabase = c.get('supabase')
    const slug = c.req.param('slug').toLowerCase()

    const { data, error } = await supabase
      .from('guide_bases')
      .update({ status: 'archived' })
      .eq('slug', slug)
      .select('id, slug, status')

    if (error) return c.json({ error: error.message }, 500)
    if (!data || data.length === 0) {
      return c.json({ error: 'Topic not found or not permitted' }, 404)
    }
    return c.json({ topic: data[0] })
  })

  // Materialize the transitive prerequisite DAG
  .get('/:slug/walkthrough', (c) => c.json({ error: 'Not implemented' }, 501))

  // Declare a TODO prerequisite
  .post('/:slug/todos', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

  // Variants under this topic
  .get('/:slug/variants', (c) => c.json({ error: 'Not implemented' }, 501))

  // Add a new variant under this topic
  .post('/:slug/variants', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

export const variantsRouter = new Hono<HonoEnv>()
  // Shows variant details: current revision content + vote tally
  .get('/:id', (c) => c.json({ error: 'Not implemented' }, 501))

  // Archive the variant
  .delete('/:id', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

  // Cast or update a vote
  .put('/:id/vote', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

  // Retract the caller's vote on this variant
  .delete('/:id/vote', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

  // Revision history for this variant
  .get('/:id/revisions', (c) => c.json({ error: 'Not implemented' }, 501))

  // Start a new draft revision
  .post('/:id/revisions', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

  // Roll back: insert a new revision copying an older snapshot
  .post('/:id/rollback', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

export const guideRevisionsRouter = new Hono<HonoEnv>()
  // A single revision snapshot (content + status)
  .get('/:id', (c) => c.json({ error: 'Not implemented' }, 501))

  // Overwrite a draft revision (pre-submit only)
  .patch('/:id', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

  // Submit for review: revision status flips to submitted and opens a review_case
  .post('/:id/submit', requireUser, (c) => c.json({ error: 'Not implemented' }, 501))

  // Rendered diff between two snapshots
  .get('/:id/diff/:otherId', (c) => c.json({ error: 'Not implemented' }, 501))
