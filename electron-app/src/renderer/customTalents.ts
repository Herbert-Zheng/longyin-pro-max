import {
  BASE_ATTRI_TYPE_NAMES,
  BaseAttriTypeName,
  CUSTOM_TALENT_CONDITION_TYPES,
  CUSTOM_TALENT_PACK_VERSION,
  CustomTalentCondition,
  CustomTalentConditionType,
  CustomTalentDefinition,
  CustomTalentEffect,
  CustomTalentPack,
  DEFAULT_CUSTOM_TALENT_DURATION_DAYS,
  HERO_SPE_ADD_DATA_TYPE_NAMES,
  HeroSpeAddDataTypeName
} from '../shared/types';

export const BASE_ATTRI_TYPE_LABELS: Record<BaseAttriTypeName, string> = {
  Str: '体魄',
  Agl: '身法',
  Inte: '智力',
  Wil: '意志',
  Con: '根骨',
  Mag: '魅力',
  Internal: '内功',
  Dodge: '轻功',
  Unique: '绝学',
  Fist: '拳掌',
  Sword: '剑法',
  Knife: '刀法',
  Long: '长兵',
  Strange: '奇门',
  Shoot: '射术',
  Med: '医术',
  Poison: '毒术',
  Knowledge: '学识',
  Speech: '口才',
  DigAndCut: '采掘',
  Plant: '采药',
  CraftEquip: '锻造',
  CraftMed: '制药',
  CraftFood: '烹饪'
};

export const CUSTOM_TALENT_CONDITION_TYPE_LABELS: Record<CustomTalentConditionType, string> = {
  stat_min: '玩家属性达到门槛',
  team_stat_sum_min: '队伍属性总和达到门槛'
};

function createId(prefix: string): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }

  return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
}

export function createEmptyCustomTalentPack(): CustomTalentPack {
  return {
    version: CUSTOM_TALENT_PACK_VERSION,
    talents: []
  };
}

export function createCustomTalentCondition(): CustomTalentCondition {
  return {
    type: 'stat_min',
    stat: 'Inte',
    min: 10
  };
}

export function createCustomTalentEffect(): CustomTalentEffect {
  return {
    effectType: 'addAttri2',
    value: 10
  };
}

export function createCustomTalent(name = '新天赋'): CustomTalentDefinition {
  return {
    id: createId('custom-talent'),
    enabled: true,
    name,
    durationDays: DEFAULT_CUSTOM_TALENT_DURATION_DAYS,
    conditions: [createCustomTalentCondition()],
    effects: [createCustomTalentEffect()]
  };
}

export function cloneCustomTalentPack(pack: CustomTalentPack): CustomTalentPack {
  return {
    version: CUSTOM_TALENT_PACK_VERSION,
    talents: pack.talents.map((talent) => ({
      id: talent.id,
      enabled: talent.enabled,
      name: talent.name,
      durationDays: talent.durationDays,
      conditions: talent.conditions.map((condition) => ({
        type: condition.type,
        stat: condition.stat,
        min: condition.min
      })),
      effects: talent.effects.map((effect) => ({
        effectType: effect.effectType,
        value: effect.value
      }))
    }))
  };
}

export function duplicateCustomTalent(talent: CustomTalentDefinition): CustomTalentDefinition {
  return {
    ...cloneCustomTalentPack({ version: CUSTOM_TALENT_PACK_VERSION, talents: [talent] }).talents[0],
    id: createId('custom-talent'),
    name: `${talent.name.trim() || '新天赋'} 副本`
  };
}

export function validateCustomTalentPack(pack: CustomTalentPack): string[] {
  const errors: string[] = [];
  const seenNames = new Set<string>();

  if (pack.version !== CUSTOM_TALENT_PACK_VERSION) {
    errors.push(`配置版本必须是 ${CUSTOM_TALENT_PACK_VERSION}。`);
  }

  pack.talents.forEach((talent, talentIndex) => {
    const displayIndex = talentIndex + 1;
    const trimmedName = talent.name.trim();
    if (!trimmedName) {
      errors.push(`第 ${displayIndex} 个天赋名称不能为空。`);
    }
    else if (seenNames.has(trimmedName)) {
      errors.push(`天赋名称不能重复：${trimmedName}`);
    }
    else {
      seenNames.add(trimmedName);
    }

    if (!Number.isInteger(talent.durationDays) || talent.durationDays < 1) {
      errors.push(`第 ${displayIndex} 个天赋的持续天数必须是大于等于 1 的整数。`);
    }

    if (talent.conditions.length === 0) {
      errors.push(`第 ${displayIndex} 个天赋至少需要 1 条条件。`);
    }

    if (talent.effects.length === 0) {
      errors.push(`第 ${displayIndex} 个天赋至少需要 1 条效果。`);
    }

    talent.conditions.forEach((condition, conditionIndex) => {
      if (!(CUSTOM_TALENT_CONDITION_TYPES as readonly string[]).includes(condition.type)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${conditionIndex + 1} 条条件类型无效。`);
      }
      if (!(BASE_ATTRI_TYPE_NAMES as readonly string[]).includes(condition.stat)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${conditionIndex + 1} 条条件属性无效。`);
      }
      if (!Number.isFinite(condition.min)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${conditionIndex + 1} 条条件最低值无效。`);
      }
    });

    talent.effects.forEach((effect, effectIndex) => {
      if (!(HERO_SPE_ADD_DATA_TYPE_NAMES as readonly string[]).includes(effect.effectType)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${effectIndex + 1} 条效果类型无效。`);
      }
      if (!Number.isFinite(effect.value)) {
        errors.push(`第 ${displayIndex} 个天赋的第 ${effectIndex + 1} 条效果数值无效。`);
      }
    });
  });

  return errors;
}

export function formatBaseAttriType(value: BaseAttriTypeName): string {
  return BASE_ATTRI_TYPE_LABELS[value] ?? value;
}

export function formatCustomTalentConditionType(value: CustomTalentConditionType): string {
  return CUSTOM_TALENT_CONDITION_TYPE_LABELS[value] ?? value;
}

export function formatHeroSpeAddDataType(value: HeroSpeAddDataTypeName): string {
  return value;
}
