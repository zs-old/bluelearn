import { Hono } from 'hono'
import { requireUser } from '../middleware/auth.middleware'
import type { HonoEnv } from '../types'
import { createSubjectSchema } from '@bluelearn/schemas'
import { zValidator } from '@hono/zod-validator'
import { slugify } from '../lib/slug'

export const subjectsRouter = new Hono<HonoEnv>()
  // List all subjects
  .get('/', async (c) => {
    const supabase =  c.get('supabase')
    const {data: subjectList, error} = await supabase
      .from('subjects')
      .select('id, slug, name')

    if (error) {
      return c.json({error: error.message}, 500);
    }
    return c.json({subjects: subjectList}, 200)
  })

  // Create a subject
  .post('/', requireUser, zValidator('json', createSubjectSchema), async (c) => {
    const supabase = c.get('supabase')
    const user = c.get('user')

    const { name } = await c.req.valid('json')
    const slug = slugify(name)
    if (!slug) {
      return c.json({ error: 'Title must contain at least one letter or number' }, 400)
    }

    // insert row to subjects
    const {data: insert_data, error: insert_error} = await supabase
      .from('subjects')
      .insert({slug: slug, name: name, creator_id: user.id})
      .select('id, slug, name')
      .single()
    if (insert_error) {
      if (insert_error.code === '23505') {
        return c.json({error: 'Error: This subject name is a duplicate of an existing subject.'}, 409)
      }
      return c.json({error: insert_error.message}, 500)
    }
    
    return c.json({subject: insert_data}, 201)
  })

  // Subject metadata only (the tagged list is a separate call)
  .get('/:slug', async (c) => {
    const supabase =  c.get('supabase')
    const slug = c.req.param('slug')
    const {data, error} = await supabase
      .from('subjects')
      .select('*')
      .eq('slug', slug)
      .maybeSingle()
    if (error) {
      return c.json({error: error.message}, 500)
    }
    if (!data) {
      return c.json({error: 'Subject not found.'}, 404)
    }
    return c.json({subject: data}, 200)
  })

  // Alphabetical list of topics carrying this subject tag
  .get('/:slug/guides', async (c) => {
    const supabase = c.get('supabase')
    const slug = c.req.param('slug')
    
    // select id of desired subject matchine inputted slug
    const {data: subject, error} = await supabase
      .from('subjects')
      .select('id')
      .eq('slug', slug)
      .maybeSingle()
    if (error) {
      return c.json({error: error.message}, 500) 
    }
    if (!subject) {
      return c.json({ error: 'Subject not found' }, 404)
    }

    // get ID of guide base matching subject ID
    const {data: guide_base_id, error: guide_error} = await supabase
      .from('guide_subjects')
      .select('guide_base_id')
      .eq('subject_id', subject.id)
    if (guide_error) {
      return c.json({error: guide_error.message}, 500)
    }

    const ids = guide_base_id.map(r => r.guide_base_id)
    if (ids.length === 0) return c.json([], 200)

    // get guide base metadate from it's ID
    const {data: guide_base_data, error: guide_base_error} = await supabase
      .from('guide_bases')
      .select('slug, title, knowledge_type')
      .in('id', ids)
      .order('title')
    if (guide_base_error) {
      return c.json({error: guide_base_error.message}, 500)
    }

    return c.json({guide_bases: guide_base_data}, 200)
  })
