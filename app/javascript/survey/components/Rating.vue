<script setup>
import { computed } from 'vue';
import { CSAT_RATINGS } from 'shared/constants/messages';

const props = defineProps({
  selectedRating: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['selectRating']);

const ratingVisuals = {
  1: {
    label: 'PÉSSIMO',
    face: 'verySad',
    colorClass: 'text-red-600',
    selectedClass: 'bg-red-50 ring-red-200',
    markerClass: 'bg-red-600 ring-red-100',
  },
  2: {
    label: 'RUIM',
    face: 'sad',
    colorClass: 'text-orange-500',
    selectedClass: 'bg-orange-50 ring-orange-200',
    markerClass: 'bg-orange-500 ring-orange-100',
  },
  3: {
    label: 'REGULAR',
    face: 'neutral',
    colorClass: 'text-slate-500',
    selectedClass: 'bg-slate-50 ring-slate-200',
    markerClass: 'bg-slate-500 ring-slate-100',
  },
  4: {
    label: 'BOM',
    face: 'happy',
    colorClass: 'text-green-600',
    selectedClass: 'bg-green-50 ring-green-200',
    markerClass: 'bg-green-600 ring-green-100',
  },
  5: {
    label: 'EXCELENTE',
    face: 'excellent',
    colorClass: 'text-amber-500',
    selectedClass: 'bg-amber-50 ring-amber-200',
    markerClass: 'bg-amber-500 ring-amber-100',
  },
};

const ratings = computed(() =>
  CSAT_RATINGS.map(rating => ({
    ...rating,
    ...ratingVisuals[rating.value],
  }))
);

const isLocked = computed(() => props.selectedRating !== null);

const isSelected = rating => rating.value === props.selectedRating;

const buttonClass = rating => [
  'relative flex min-w-0 flex-col items-center justify-start gap-1.5 px-0 pt-7 pb-2 outline-none transition duration-300 sm:px-2',
  'focus-visible:rounded-md focus-visible:ring-2 focus-visible:ring-n-brand',
  rating.value < ratings.value.length ? 'border-r border-n-weak' : '',
  isSelected(rating)
    ? ['z-10 scale-105 rounded-md ring-2 shadow-sm', rating.selectedClass]
    : 'hover:-translate-y-0.5 hover:bg-n-alpha-1',
  isLocked.value && !isSelected(rating) ? 'opacity-40' : 'opacity-100',
  isLocked.value ? 'cursor-default' : 'cursor-pointer',
];

const labelClass = rating => [
  'max-w-full text-center text-[0.5rem] font-bold uppercase leading-tight sm:text-xs',
  rating.colorClass,
];

const markerClass = rating => [
  'absolute top-0 flex h-5 w-5 items-center justify-center rounded-full text-white ring-4 animate-bounce',
  rating.markerClass,
];

const onClick = rating => {
  if (isLocked.value) {
    return;
  }

  emit('selectRating', rating.value);
};
</script>

<template>
  <div class="mb-2 w-full">
    <div class="grid w-full grid-cols-5 py-4">
      <button
        v-for="rating in ratings"
        :key="rating.key"
        type="button"
        :aria-label="rating.label"
        :aria-pressed="isSelected(rating)"
        :disabled="isLocked"
        :class="buttonClass(rating)"
        @click="onClick(rating)"
      >
        <span v-if="isSelected(rating)" :class="markerClass(rating)">
          <svg
            aria-hidden="true"
            class="h-3.5 w-3.5"
            fill="none"
            viewBox="0 0 16 16"
          >
            <path
              d="M3.25 8.1 6.2 11l6.55-6.5"
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
            />
          </svg>
        </span>
        <svg
          aria-hidden="true"
          class="h-10 w-10 shrink-0 sm:h-12 sm:w-12"
          :class="rating.colorClass"
          fill="none"
          viewBox="0 0 48 48"
        >
          <circle
            cx="24"
            cy="24"
            fill="white"
            r="17"
            stroke="currentColor"
            stroke-width="2.4"
          />
          <g fill="currentColor">
            <circle cx="18" cy="19" r="2.1" />
            <circle cx="30" cy="19" r="2.1" />
          </g>
          <path
            v-if="rating.face === 'verySad'"
            d="M15.5 33c2.3-4.5 5.3-6.7 8.5-6.7s6.2 2.2 8.5 6.7"
            stroke="currentColor"
            stroke-linecap="round"
            stroke-width="2.6"
          />
          <path
            v-else-if="rating.face === 'sad'"
            d="M16.5 31c2.1-2.6 4.6-3.9 7.5-3.9s5.4 1.3 7.5 3.9"
            stroke="currentColor"
            stroke-linecap="round"
            stroke-width="2.6"
          />
          <path
            v-else-if="rating.face === 'neutral'"
            d="M17 30h14"
            stroke="currentColor"
            stroke-linecap="round"
            stroke-width="2.6"
          />
          <path
            v-else-if="rating.face === 'happy'"
            d="M16 28c2.2 4.5 4.9 6.7 8 6.7s5.8-2.2 8-6.7"
            stroke="currentColor"
            stroke-linecap="round"
            stroke-width="2.6"
          />
          <path
            v-else
            d="M15 27.5c2.5 5.2 5.5 7.8 9 7.8s6.5-2.6 9-7.8"
            stroke="currentColor"
            stroke-linecap="round"
            stroke-width="2.8"
          />
        </svg>
        <span :class="labelClass(rating)">
          {{ rating.label }}
        </span>
      </button>
    </div>
  </div>
</template>
