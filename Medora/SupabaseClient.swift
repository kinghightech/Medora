//
//  SupabaseClient.swift
//  Medora
//
//  Shared Supabase client for Auth and profile data.
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://konkupewlocdjpznpgac.supabase.co")!,
    supabaseKey: "sb_publishable_olV4Z8LpVpQJVRCeVKOTOA_HvHkS0Kk"
)
