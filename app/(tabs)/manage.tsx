import { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView, ActivityIndicator, Modal } from 'react-native';
import { router } from 'expo-router';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import { Plus, FileText, History, ChevronDown } from 'lucide-react-native';

interface Tournament {
  id: string;
  name: string;
  start_date: string;
  end_date: string;
  status: 'draft' | 'active' | 'closed';
  join_code: string;
  created_at: string;
}

type DurationOption = {
  label: string;
  days: number;
};

const DURATION_OPTIONS: DurationOption[] = [
  { label: '3 days', days: 3 },
  { label: '7 days', days: 7 },
  { label: '2 weeks', days: 14 },
  { label: '4 weeks', days: 28 },
];

export default function ManageTournamentsScreen() {
  const { user } = useAuth();
  const [activeView, setActiveView] = useState<'menu' | 'drafts' | 'past'>('menu');
  const [draftTournaments, setDraftTournaments] = useState<Tournament[]>([]);
  const [pastTournaments, setPastTournaments] = useState<Tournament[]>([]);
  const [loading, setLoading] = useState(false);
  const [createModalVisible, setCreateModalVisible] = useState(false);

  const [duration, setDuration] = useState<DurationOption>(DURATION_OPTIONS[0]);
  const [showDurationPicker, setShowDurationPicker] = useState(false);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [userDisplayName, setUserDisplayName] = useState('');

  useEffect(() => {
    loadUserDisplayName();
  }, [user]);

  const loadUserDisplayName = async () => {
    if (!user) return;

    const { data } = await supabase
      .from('users')
      .select('display_name')
      .eq('id', user.id)
      .maybeSingle();

    if (data) {
      setUserDisplayName(data.display_name);
    }
  };

  const loadDraftTournaments = async () => {
    if (!user) return;
    setLoading(true);

    const { data, error } = await supabase
      .from('tournaments')
      .select('*')
      .eq('created_by', user.id)
      .eq('status', 'draft')
      .order('created_at', { ascending: false });

    if (!error && data) {
      setDraftTournaments(data);
    }

    setLoading(false);
  };

  const loadPastTournaments = async () => {
    if (!user) return;
    setLoading(true);

    const { data, error } = await supabase
      .from('tournaments')
      .select('*')
      .eq('created_by', user.id)
      .eq('status', 'closed')
      .order('created_at', { ascending: false });

    if (!error && data) {
      setPastTournaments(data);
    }

    setLoading(false);
  };

  const handleCreateTournament = async () => {
    if (!userDisplayName) {
      setError('Unable to load user information');
      return;
    }

    setSaving(true);
    setError('');

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const endDate = new Date(today);
    endDate.setDate(endDate.getDate() + duration.days);

    const tournamentName = `${userDisplayName}'s tournament`;

    const { data, error: createError } = await supabase
      .from('tournaments')
      .insert([
        {
          name: tournamentName,
          start_date: today.toISOString(),
          end_date: endDate.toISOString(),
          created_by: user!.id,
        },
      ])
      .select()
      .single();

    if (createError) {
      setSaving(false);
      setError(createError.message);
      return;
    }

    if (data) {
      const { error: participantError } = await supabase
        .from('tournament_participants')
        .insert([
          {
            tournament_id: data.id,
            user_id: user!.id,
          },
        ]);

      setSaving(false);

      if (participantError) {
        setError('Tournament created but failed to add you as participant');
      } else {
        setCreateModalVisible(false);
        setDuration(DURATION_OPTIONS[0]);
        router.push(`/draft-tournament/${data.id}`);
      }
    } else {
      setSaving(false);
    }
  };

  const renderMenu = () => (
    <ScrollView style={styles.content}>
      <View style={styles.menuGrid}>
        <TouchableOpacity
          style={styles.menuCard}
          onPress={() => setCreateModalVisible(true)}
        >
          <View style={[styles.menuIconContainer, { backgroundColor: '#10b981' }]}>
            <Plus size={32} color="#fff" />
          </View>
          <Text style={styles.menuCardTitle}>Create Tournament</Text>
          <Text style={styles.menuCardSubtitle}>Start a new tournament</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.menuCard}
          onPress={() => {
            setActiveView('drafts');
            loadDraftTournaments();
          }}
        >
          <View style={[styles.menuIconContainer, { backgroundColor: '#f59e0b' }]}>
            <FileText size={32} color="#fff" />
          </View>
          <Text style={styles.menuCardTitle}>Open Drafts</Text>
          <Text style={styles.menuCardSubtitle}>Tournaments awaiting players</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.menuCard}
          onPress={() => {
            setActiveView('past');
            loadPastTournaments();
          }}
        >
          <View style={[styles.menuIconContainer, { backgroundColor: '#6b7280' }]}>
            <History size={32} color="#fff" />
          </View>
          <Text style={styles.menuCardTitle}>Past Tournaments</Text>
          <Text style={styles.menuCardSubtitle}>View completed tournaments</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );

  const renderDrafts = () => (
    <ScrollView style={styles.content}>
      <TouchableOpacity
        style={styles.backButton}
        onPress={() => setActiveView('menu')}
      >
        <Text style={styles.backButtonText}>← Back to Menu</Text>
      </TouchableOpacity>

      {loading ? (
        <ActivityIndicator color="#10b981" style={{ marginTop: 40 }} />
      ) : draftTournaments.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyText}>No draft tournaments</Text>
          <Text style={styles.emptySubtext}>Create a tournament to get started</Text>
        </View>
      ) : (
        draftTournaments.map(tournament => (
          <TouchableOpacity
            key={tournament.id}
            style={styles.tournamentCard}
            onPress={() => router.push(`/draft-tournament/${tournament.id}`)}
          >
            <View style={styles.tournamentHeader}>
              <Text style={styles.tournamentName}>{tournament.name}</Text>
              <View style={[styles.statusBadge, { backgroundColor: '#f59e0b' }]}>
                <Text style={styles.statusText}>DRAFT</Text>
              </View>
            </View>
            <Text style={styles.tournamentDate}>
              {new Date(tournament.start_date).toLocaleDateString()} - {new Date(tournament.end_date).toLocaleDateString()}
            </Text>
            <Text style={styles.joinCodeText}>Join Code: {tournament.join_code}</Text>
          </TouchableOpacity>
        ))
      )}
    </ScrollView>
  );

  const renderPast = () => (
    <ScrollView style={styles.content}>
      <TouchableOpacity
        style={styles.backButton}
        onPress={() => setActiveView('menu')}
      >
        <Text style={styles.backButtonText}>← Back to Menu</Text>
      </TouchableOpacity>

      {loading ? (
        <ActivityIndicator color="#10b981" style={{ marginTop: 40 }} />
      ) : pastTournaments.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyText}>No past tournaments</Text>
          <Text style={styles.emptySubtext}>Completed tournaments will appear here</Text>
        </View>
      ) : (
        pastTournaments.map(tournament => (
          <TouchableOpacity
            key={tournament.id}
            style={styles.tournamentCard}
            onPress={() => router.push(`/tournament/${tournament.id}`)}
          >
            <View style={styles.tournamentHeader}>
              <Text style={styles.tournamentName}>{tournament.name}</Text>
              <View style={[styles.statusBadge, { backgroundColor: '#6b7280' }]}>
                <Text style={styles.statusText}>CLOSED</Text>
              </View>
            </View>
            <Text style={styles.tournamentDate}>
              {new Date(tournament.start_date).toLocaleDateString()} - {new Date(tournament.end_date).toLocaleDateString()}
            </Text>
          </TouchableOpacity>
        ))
      )}
    </ScrollView>
  );

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Tournament Management</Text>
      </View>

      {activeView === 'menu' && renderMenu()}
      {activeView === 'drafts' && renderDrafts()}
      {activeView === 'past' && renderPast()}

      <Modal
        visible={createModalVisible}
        transparent
        animationType="slide"
        onRequestClose={() => setCreateModalVisible(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Create Tournament</Text>

            <View style={styles.infoBox}>
              <Text style={styles.infoBoxLabel}>Tournament Name</Text>
              <Text style={styles.infoBoxValue}>
                {userDisplayName ? `${userDisplayName}'s tournament` : 'Loading...'}
              </Text>
            </View>

            <Text style={styles.inputLabel}>Duration</Text>
            <TouchableOpacity
              style={styles.dropdownButton}
              onPress={() => setShowDurationPicker(!showDurationPicker)}
              disabled={saving}
            >
              <Text style={styles.dropdownButtonText}>{duration.label}</Text>
              <ChevronDown size={20} color="#666" />
            </TouchableOpacity>

            {showDurationPicker && (
              <View style={styles.dropdownList}>
                {DURATION_OPTIONS.map((option) => (
                  <TouchableOpacity
                    key={option.days}
                    style={[
                      styles.dropdownItem,
                      option.days === duration.days && styles.dropdownItemSelected,
                    ]}
                    onPress={() => {
                      setDuration(option);
                      setShowDurationPicker(false);
                    }}
                  >
                    <Text
                      style={[
                        styles.dropdownItemText,
                        option.days === duration.days && styles.dropdownItemTextSelected,
                      ]}
                    >
                      {option.label}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            )}

            <View style={styles.infoBox}>
              <Text style={styles.infoBoxLabel}>Start Date</Text>
              <Text style={styles.infoBoxValue}>
                When tournament is started
              </Text>
            </View>

            {error ? <Text style={styles.error}>{error}</Text> : null}

            <View style={styles.modalButtons}>
              <TouchableOpacity
                style={[styles.modalButton, styles.modalButtonCancel]}
                onPress={() => {
                  setCreateModalVisible(false);
                  setDuration(DURATION_OPTIONS[0]);
                  setShowDurationPicker(false);
                  setError('');
                }}
                disabled={saving}
              >
                <Text style={styles.modalButtonTextCancel}>Cancel</Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.modalButton, styles.modalButtonSave, saving && styles.buttonDisabled]}
                onPress={handleCreateTournament}
                disabled={saving}
              >
                {saving ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={styles.modalButtonTextSave}>Create</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  header: {
    backgroundColor: '#10b981',
    padding: 24,
    paddingTop: 60,
    paddingBottom: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#fff',
  },
  content: {
    flex: 1,
    padding: 16,
  },
  menuGrid: {
    gap: 16,
  },
  menuCard: {
    backgroundColor: '#fff',
    padding: 24,
    borderRadius: 16,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  menuIconContainer: {
    width: 72,
    height: 72,
    borderRadius: 36,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
  },
  menuCardTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#1a1a1a',
    marginBottom: 4,
  },
  menuCardSubtitle: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
  },
  backButton: {
    marginBottom: 16,
  },
  backButtonText: {
    fontSize: 16,
    color: '#10b981',
    fontWeight: '500',
  },
  tournamentCard: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 12,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  tournamentHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  tournamentName: {
    fontSize: 18,
    fontWeight: '600',
    color: '#1a1a1a',
    flex: 1,
  },
  statusBadge: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  tournamentDate: {
    fontSize: 14,
    color: '#666',
    marginBottom: 4,
  },
  joinCodeText: {
    fontSize: 14,
    color: '#10b981',
    fontWeight: '500',
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 60,
    paddingHorizontal: 40,
  },
  emptyText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#1a1a1a',
    marginBottom: 8,
  },
  emptySubtext: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    padding: 24,
  },
  modalContent: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 24,
  },
  modalTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#1a1a1a',
    marginBottom: 20,
  },
  inputLabel: {
    fontSize: 14,
    color: '#666',
    marginBottom: 8,
    marginTop: 8,
  },
  infoBox: {
    backgroundColor: '#f9fafb',
    borderRadius: 8,
    padding: 16,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: '#e5e7eb',
  },
  infoBoxLabel: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
    fontWeight: '500',
  },
  infoBoxValue: {
    fontSize: 16,
    color: '#1a1a1a',
    fontWeight: '600',
  },
  dropdownButton: {
    backgroundColor: '#f9fafb',
    borderRadius: 8,
    padding: 14,
    fontSize: 16,
    borderWidth: 1,
    borderColor: '#e5e7eb',
    marginBottom: 16,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  dropdownButtonText: {
    fontSize: 16,
    color: '#1a1a1a',
  },
  dropdownList: {
    backgroundColor: '#fff',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#e5e7eb',
    marginBottom: 16,
    overflow: 'hidden',
  },
  dropdownItem: {
    padding: 14,
    borderBottomWidth: 1,
    borderBottomColor: '#e5e7eb',
  },
  dropdownItemSelected: {
    backgroundColor: '#f0fdf4',
  },
  dropdownItemText: {
    fontSize: 16,
    color: '#1a1a1a',
  },
  dropdownItemTextSelected: {
    color: '#10b981',
    fontWeight: '600',
  },
  error: {
    color: '#ef4444',
    fontSize: 14,
    marginBottom: 16,
  },
  modalButtons: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 16,
  },
  modalButton: {
    flex: 1,
    padding: 14,
    borderRadius: 8,
    alignItems: 'center',
  },
  modalButtonCancel: {
    backgroundColor: '#f3f4f6',
  },
  modalButtonSave: {
    backgroundColor: '#10b981',
  },
  modalButtonTextCancel: {
    color: '#1a1a1a',
    fontSize: 16,
    fontWeight: '600',
  },
  modalButtonTextSave: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  buttonDisabled: {
    opacity: 0.6,
  },
});
